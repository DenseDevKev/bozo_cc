use bozo_proto::ipc::message::{HeadphoneState, IpcRequest, IpcResponse, StateUpdate};
use bozo_proto::ipc::transport::{IpcReader, IpcWriter};
use bozo_proto::protocol::{audio_modes, cnc, power, standby};
use std::path::Path;
use std::sync::Arc;
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{broadcast, mpsc, RwLock};
use tracing::{debug, error, info, warn};

use crate::ble::connection::BleCommand;
use crate::event::DaemonEvent;

/// Run the Unix socket server.
pub async fn run_server(
    socket_path: &Path,
    state: Arc<RwLock<HeadphoneState>>,
    command_tx: mpsc::Sender<BleCommand>,
    event_tx: broadcast::Sender<DaemonEvent>,
) -> anyhow::Result<()> {
    // Remove stale socket file
    if socket_path.exists() {
        std::fs::remove_file(socket_path)?;
    }

    let listener = UnixListener::bind(socket_path)?;
    info!("listening on {}", socket_path.display());

    loop {
        match listener.accept().await {
            Ok((stream, _addr)) => {
                info!("client connected");
                let state = state.clone();
                let command_tx = command_tx.clone();
                let event_rx = event_tx.subscribe();
                tokio::spawn(async move {
                    if let Err(e) =
                        handle_client(stream, state, command_tx, event_rx).await
                    {
                        warn!("client disconnected: {}", e);
                    }
                });
            }
            Err(e) => {
                error!("accept error: {}", e);
            }
        }
    }
}

async fn handle_client(
    stream: UnixStream,
    state: Arc<RwLock<HeadphoneState>>,
    command_tx: mpsc::Sender<BleCommand>,
    mut event_rx: broadcast::Receiver<DaemonEvent>,
) -> anyhow::Result<()> {
    let (read_half, write_half) = stream.into_split();
    let mut reader = IpcReader::new(read_half);
    let mut writer = IpcWriter::new(write_half);

    loop {
        tokio::select! {
            // Handle incoming requests from the client
            request = reader.read::<IpcRequest>() => {
                match request {
                    Ok(Some(req)) => {
                        let response = handle_request(req, &state, &command_tx).await;
                        writer.write(&response).await?;
                    }
                    Ok(None) => {
                        info!("client disconnected (EOF)");
                        return Ok(());
                    }
                    Err(e) => {
                        warn!("client read error: {}", e);
                        return Err(e.into());
                    }
                }
            }

            // Push state updates to the client
            event = event_rx.recv() => {
                debug!("client handler got event: {:?}", event);
                match event {
                    Ok(DaemonEvent::PacketReceived(_)) => {
                        // Raw packets are processed by the state manager,
                        // which emits StateUpdated events.
                    }
                    Ok(DaemonEvent::StateUpdated(update)) => {
                        debug!("pushing state update to client: {:?}", update);
                        writer.write(&IpcResponse::StateUpdate(update)).await?;
                    }
                    Ok(DaemonEvent::Connected) => {
                        let update = StateUpdate::Connection { connected: true };
                        writer.write(&IpcResponse::StateUpdate(update)).await?;
                    }
                    Ok(DaemonEvent::Disconnected) => {
                        let update = StateUpdate::Connection { connected: false };
                        writer.write(&IpcResponse::StateUpdate(update)).await?;
                    }
                    Err(broadcast::error::RecvError::Lagged(n)) => {
                        warn!("client lagged by {} events", n);
                    }
                    Err(broadcast::error::RecvError::Closed) => {
                        return Ok(());
                    }
                }
            }
        }
    }
}

async fn handle_request(
    request: IpcRequest,
    state: &Arc<RwLock<HeadphoneState>>,
    command_tx: &mpsc::Sender<BleCommand>,
) -> IpcResponse {
    match request {
        IpcRequest::GetState => {
            let s = state.read().await.clone();
            IpcResponse::State(s)
        }
        IpcRequest::SetCnc { level, enabled } => {
            let packet = cnc::set(level, enabled);
            if command_tx.send(BleCommand::SendPacket(packet)).await.is_ok() {
                IpcResponse::Ok
            } else {
                IpcResponse::Error {
                    message: "not connected".into(),
                }
            }
        }
        IpcRequest::SetStandbyTimer { minutes } => {
            let packet = standby::set(minutes);
            if command_tx.send(BleCommand::SendPacket(packet)).await.is_ok() {
                IpcResponse::Ok
            } else {
                IpcResponse::Error {
                    message: "not connected".into(),
                }
            }
        }
        IpcRequest::PowerOff => {
            let packet = power::power_off();
            if command_tx.send(BleCommand::SendPacket(packet)).await.is_ok() {
                IpcResponse::Ok
            } else {
                IpcResponse::Error {
                    message: "not connected".into(),
                }
            }
        }
        IpcRequest::Disconnect => {
            if command_tx.send(BleCommand::Disconnect).await.is_ok() {
                IpcResponse::Ok
            } else {
                IpcResponse::Error {
                    message: "not connected".into(),
                }
            }
        }
        IpcRequest::SetAudioMode { mode_index } => {
            let packet = audio_modes::set_current_mode(mode_index);
            if command_tx.send(BleCommand::SendPacket(packet)).await.is_ok() {
                IpcResponse::Ok
            } else {
                IpcResponse::Error {
                    message: "not connected".into(),
                }
            }
        }
        IpcRequest::Reconnect => {
            // Reconnect is handled at a higher level; for now just ack
            IpcResponse::Ok
        }
    }
}
