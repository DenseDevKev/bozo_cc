mod ble;
mod event;
mod server;
mod state;

use ble::connection::{BleCommand, ConnectionManager};
use ble::scanner;
use event::DaemonEvent;
use state::StateManager;

use std::path::PathBuf;
use std::time::Duration;
use tokio::sync::{broadcast, mpsc};
use tracing::{error, info, warn};

const SOCKET_PATH: &str = "/tmp/bozod.sock";
const SCAN_TIMEOUT: Duration = Duration::from_secs(5);

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "bozod=info".into()),
        )
        .init();

    let args: Vec<String> = std::env::args().collect();
    let scan_only = args.iter().any(|a| a == "--scan-only");

    info!("bozod starting");

    // Get BLE adapter
    let adapter = scanner::get_adapter().await?;
    info!("using adapter: {:?}", btleplug::api::Central::adapter_info(&adapter).await?);

    if scan_only {
        scanner::list_bose_devices(&adapter, SCAN_TIMEOUT).await?;
        return Ok(());
    }

    // Event bus
    let (event_tx, _) = broadcast::channel::<DaemonEvent>(256);

    // BLE command channel
    let (command_tx, command_rx) = mpsc::channel::<BleCommand>(32);

    // State manager — subscribe BEFORE connect so we don't miss events
    let state_manager = StateManager::new(event_tx.clone());
    let state = state_manager.state.clone();
    let sm_state = state_manager.state.clone();
    let mut state_event_rx = event_tx.subscribe();
    tokio::spawn(async move {
        loop {
            match state_event_rx.recv().await {
                Ok(DaemonEvent::PacketReceived(packet)) => {
                    state_manager.process_packet(&packet).await;
                }
                Ok(DaemonEvent::StateUpdated(ref update)) => {
                    info!("state updated: {:?}", update);
                }
                Ok(DaemonEvent::Connected) => {
                    let mut s = sm_state.write().await;
                    s.connected = true;
                    info!("state: connected");
                }
                Ok(DaemonEvent::Disconnected) => {
                    let mut s = sm_state.write().await;
                    s.connected = false;
                    info!("state: disconnected");
                }
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    warn!("state manager lagged by {} events", n);
                }
                Err(broadcast::error::RecvError::Closed) => {
                    break;
                }
            }
        }
    });

    // Spawn socket server (ready before connection so clients can connect early)
    let socket_path = PathBuf::from(SOCKET_PATH);
    let server_state = state.clone();
    let server_command_tx = command_tx.clone();
    let server_event_tx = event_tx.clone();
    let _server_handle = tokio::spawn(async move {
        if let Err(e) =
            server::run_server(&socket_path, server_state, server_command_tx, server_event_tx)
                .await
        {
            error!("server error: {}", e);
        }
    });

    // Find and connect to headphones
    let peripheral = scanner::find_bose_device(&adapter, SCAN_TIMEOUT).await?;
    let mut conn = ConnectionManager::new(peripheral, event_tx.clone(), command_rx);
    conn.connect().await?;

    // Spawn connection manager task — must be running BEFORE sending queries
    // so it can process the responses via BLE notifications
    let initial_queries = StateManager::initial_queries();
    let query_tx = command_tx.clone();
    let conn_handle = tokio::spawn(async move {
        if let Err(e) = conn.run().await {
            error!("connection manager error: {}", e);
        }
    });

    // Give the notification listener a moment to start
    tokio::time::sleep(Duration::from_millis(200)).await;

    // Send initial queries via command channel so they go through the running connection
    for query in initial_queries {
        if let Err(e) = query_tx.send(BleCommand::SendPacket(query)).await {
            warn!("failed to send initial query: {}", e);
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    info!("bozod running (socket: {})", SOCKET_PATH);

    // Wait for shutdown signal
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            info!("received Ctrl+C, shutting down");
        }
        _ = conn_handle => {
            warn!("connection manager exited");
        }
    }

    // Cleanup
    let _ = std::fs::remove_file(SOCKET_PATH);
    info!("bozod stopped");

    Ok(())
}
