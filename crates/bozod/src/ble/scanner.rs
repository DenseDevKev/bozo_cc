use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter};
use btleplug::platform::{Adapter, Manager, Peripheral};
use std::time::Duration;
use tracing::info;
use uuid::Uuid;

/// Bose BMAP BLE service UUID.
pub const BMAP_SERVICE_UUID: Uuid = Uuid::from_u128(0x0000febe_0000_0000_0000_000000000000);

/// Known Bose device name substrings for matching.
const BOSE_NAME_PATTERNS: &[&str] = &["bose", "adjuster"];

/// Get the first available Bluetooth adapter.
pub async fn get_adapter() -> anyhow::Result<Adapter> {
    let manager = Manager::new().await?;
    let adapters = manager.adapters().await?;
    adapters
        .into_iter()
        .next()
        .ok_or_else(|| anyhow::anyhow!("no Bluetooth adapters found"))
}

/// Check if a device name looks like a Bose headphone.
fn is_bose_name(name: &str) -> bool {
    let lower = name.to_lowercase();
    BOSE_NAME_PATTERNS.iter().any(|p| lower.contains(p))
}

/// Scan for Bose headphones and return the first one found.
/// Scans with no UUID filter to also find already-connected devices,
/// then matches by name or BMAP service UUID.
pub async fn find_bose_device(
    adapter: &Adapter,
    timeout: Duration,
) -> anyhow::Result<Peripheral> {
    info!("scanning for Bose devices (timeout: {:?})...", timeout);

    // Scan without UUID filter so we can find already-connected devices
    adapter.start_scan(ScanFilter::default()).await?;

    tokio::time::sleep(timeout).await;
    adapter.stop_scan().await?;

    let peripherals = adapter.peripherals().await?;
    info!("found {} peripheral(s) total", peripherals.len());

    for peripheral in &peripherals {
        if let Some(props) = peripheral.properties().await? {
            let name = props.local_name.as_deref().unwrap_or("");

            let by_uuid = props.services.contains(&BMAP_SERVICE_UUID);
            let by_name = !name.is_empty() && is_bose_name(name);

            if by_uuid || by_name {
                info!(
                    "identified Bose device: \"{}\" (addr: {}, by_uuid: {}, by_name: {})",
                    name,
                    peripheral.address(),
                    by_uuid,
                    by_name
                );
                return Ok(peripheral.clone());
            }
        }
    }

    Err(anyhow::anyhow!(
        "no Bose device found after {:?} scan",
        timeout
    ))
}

/// List all discovered devices (for --scan-only mode).
/// Shows all devices, highlighting Bose ones.
pub async fn list_bose_devices(adapter: &Adapter, timeout: Duration) -> anyhow::Result<()> {
    info!("scanning for devices (timeout: {:?})...", timeout);

    adapter.start_scan(ScanFilter::default()).await?;

    tokio::time::sleep(timeout).await;
    adapter.stop_scan().await?;

    let peripherals = adapter.peripherals().await?;
    let mut bose_count = 0;

    for peripheral in &peripherals {
        if let Some(props) = peripheral.properties().await? {
            let name = props.local_name.as_deref().unwrap_or("");
            if name.is_empty() {
                continue; // skip unnamed devices
            }

            let by_uuid = props.services.contains(&BMAP_SERVICE_UUID);
            let by_name = is_bose_name(name);
            let marker = if by_uuid || by_name {
                bose_count += 1;
                " <-- BOSE"
            } else {
                ""
            };

            println!(
                "  {} (addr: {}, rssi: {:?}, services: {}){}",
                name,
                peripheral.address(),
                props.rssi,
                props.services.len(),
                marker
            );
        }
    }

    println!("  ---");
    println!(
        "  {} total named device(s), {} Bose device(s)",
        peripherals.len(),
        bose_count
    );

    Ok(())
}
