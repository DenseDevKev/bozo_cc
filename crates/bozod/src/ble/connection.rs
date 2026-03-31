use btleplug::api::{Characteristic, Peripheral as _, WriteType};
use btleplug::platform::Peripheral;
use bozo_proto::bmap::segment::{self, Reassembler};
use bozo_proto::bmap::packet::BmapPacket;
use futures::StreamExt;
use tokio::sync::{broadcast, mpsc};
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use crate::event::DaemonEvent;

/// Unsecure BMAP characteristic UUID.
const RWN_UNSECURE_UUID: Uuid =
    Uuid::from_u128(0xD417C028_9818_4354_99D1_2AC09D074591);
/// Secure BMAP characteristic UUID.
const RWN_SECURE_UUID: Uuid =
    Uuid::from_u128(0xC65B8F2F_AEE2_4C89_B758_BC4892D6F2D8);

/// Commands that can be sent to the connection manager.
#[derive(Debug)]
pub enum BleCommand {
    SendPacket(BmapPacket),
    Disconnect,
}

/// Manages the BLE connection to the headphones.
pub struct ConnectionManager {
    peripheral: Peripheral,
    characteristic: Option<Characteristic>,
    event_tx: broadcast::Sender<DaemonEvent>,
    command_rx: mpsc::Receiver<BleCommand>,
}

impl ConnectionManager {
    pub fn new(
        peripheral: Peripheral,
        event_tx: broadcast::Sender<DaemonEvent>,
        command_rx: mpsc::Receiver<BleCommand>,
    ) -> Self {
        Self {
            peripheral,
            characteristic: None,
            event_tx,
            command_rx,
        }
    }

    /// Connect to the peripheral and discover the BMAP characteristic.
    pub async fn connect(&mut self) -> anyhow::Result<()> {
        if !self.peripheral.is_connected().await? {
            info!("connecting to peripheral...");
            self.peripheral.connect().await?;
        }
        info!("connected, discovering services...");

        self.peripheral.discover_services().await?;

        // Find the BMAP characteristic (try secure first, then unsecure)
        let characteristic = self.find_bmap_characteristic()?;
        info!("found BMAP characteristic: {}", characteristic.uuid);

        // Subscribe to notifications
        self.peripheral.subscribe(&characteristic).await?;
        info!("subscribed to notifications");

        self.characteristic = Some(characteristic);
        let _ = self.event_tx.send(DaemonEvent::Connected);
        Ok(())
    }

    fn find_bmap_characteristic(&self) -> anyhow::Result<Characteristic> {
        let chars = self.peripheral.characteristics();

        // Try secure first
        if let Some(c) = chars.iter().find(|c| c.uuid == RWN_SECURE_UUID) {
            info!("using secure characteristic");
            return Ok(c.clone());
        }

        // Fall back to unsecure
        if let Some(c) = chars.iter().find(|c| c.uuid == RWN_UNSECURE_UUID) {
            info!("using unsecure characteristic");
            return Ok(c.clone());
        }

        // Log all found characteristics for debugging
        warn!("BMAP characteristic not found. Available characteristics:");
        for c in &chars {
            warn!("  service={} char={} props={:?}", c.service_uuid, c.uuid, c.properties);
        }

        Err(anyhow::anyhow!(
            "BMAP characteristic not found (tried secure {} and unsecure {})",
            RWN_SECURE_UUID,
            RWN_UNSECURE_UUID
        ))
    }

    /// Send a BMAP packet to the headphones.
    pub async fn send_packet(&self, packet: &BmapPacket) -> anyhow::Result<()> {
        let characteristic = self
            .characteristic
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("not connected"))?;

        let raw = packet.to_bytes();
        debug!("sending packet: {:02x?}", raw);

        // Segment the raw BMAP data. For single-segment packets the segment
        // header 0x00 doubles as the framing byte the device expects; for
        // multi-segment packets the headers carry the segment indices — no
        // extra framing byte is needed (matches the Bose app behaviour).
        let segments = segment::segment(&raw);

        for seg in &segments {
            self.peripheral
                .write(characteristic, seg, WriteType::WithoutResponse)
                .await?;
        }

        Ok(())
    }

    /// Run the connection event loop.
    pub async fn run(&mut self) -> anyhow::Result<()> {
        let characteristic = self
            .characteristic
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("not connected - call connect() first"))?
            .clone();

        let mut notifications = self.peripheral.notifications().await?;
        let mut reassembler = Reassembler::new();

        info!("connection manager running");

        loop {
            tokio::select! {
                // Handle incoming BLE notifications
                notification = notifications.next() => {
                    match notification {
                        Some(notif) if notif.uuid == characteristic.uuid => {
                            debug!("BLE notification: {:02x?}", notif.value);
                            match reassembler.feed(&notif.value) {
                                Ok(Some(data)) => {
                                    // Complete packet received, parse BMAP packets
                                    // The reassembled data is raw BMAP — the 0x00 framing
                                    // byte is only prepended on the write/send path and is
                                    // NOT present in device notifications.
                                    for result in BmapPacket::parse_many(&data) {
                                        match result {
                                            Ok(packet) => {
                                                debug!("received BMAP packet: {:?}", packet);
                                                let _ = self.event_tx.send(
                                                    DaemonEvent::PacketReceived(packet),
                                                );
                                            }
                                            Err(e) => {
                                                warn!("failed to parse BMAP packet: {}", e);
                                            }
                                        }
                                    }
                                }
                                Ok(None) => {
                                    // More segments expected
                                    debug!("waiting for more segments...");
                                }
                                Err(e) => {
                                    warn!("segment reassembly error: {}", e);
                                }
                            }
                        }
                        Some(_) => {
                            // Notification from a different characteristic, ignore
                        }
                        None => {
                            warn!("notification stream ended (disconnected?)");
                            let _ = self.event_tx.send(DaemonEvent::Disconnected);
                            return Ok(());
                        }
                    }
                }

                // Handle commands from the daemon
                cmd = self.command_rx.recv() => {
                    match cmd {
                        Some(BleCommand::SendPacket(packet)) => {
                            if let Err(e) = self.send_packet(&packet).await {
                                error!("failed to send packet: {}", e);
                            }
                        }
                        Some(BleCommand::Disconnect) => {
                            info!("disconnect requested");
                            let _ = self.peripheral.disconnect().await;
                            let _ = self.event_tx.send(DaemonEvent::Disconnected);
                            return Ok(());
                        }
                        None => {
                            info!("command channel closed, shutting down");
                            return Ok(());
                        }
                    }
                }
            }
        }
    }
}
