use bozo_proto::ipc::{
    message::{IpcRequest, IpcResponse},
    transport::{IpcReader, IpcWriter},
};
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;
use tokio::net::UnixStream;
use tokio::process::{Child, Command};
use tokio::sync::mpsc;

const SOCKET_PATH: &str = "/tmp/bozod.sock";
const DAEMON_STARTUP_TIMEOUT: Duration = Duration::from_secs(15);
const DAEMON_POLL_INTERVAL: Duration = Duration::from_millis(200);

pub struct IpcClient {
    writer: IpcWriter<tokio::io::WriteHalf<UnixStream>>,
    /// If we spawned the daemon, hold the child handle so it doesn't get killed on drop.
    _daemon: Option<Child>,
}

impl IpcClient {
    /// Connect to the daemon, spawning it if necessary.
    /// Returns the client (for sending) and a receiver for incoming responses.
    pub async fn connect() -> anyhow::Result<(Self, mpsc::UnboundedReceiver<IpcResponse>)> {
        // Try existing daemon first
        let (stream, daemon) = match UnixStream::connect(SOCKET_PATH).await {
            Ok(stream) => (stream, None),
            Err(_) => {
                // Spawn daemon and wait for socket
                let child = spawn_daemon()?;
                let stream = wait_for_socket().await?;
                (stream, Some(child))
            }
        };

        let (read_half, write_half) = tokio::io::split(stream);
        let mut writer = IpcWriter::new(write_half);
        let (tx, rx) = mpsc::unbounded_channel();

        // Request initial state
        writer.write(&IpcRequest::GetState).await?;

        // Spawn reader task
        tokio::spawn(async move {
            let mut reader = IpcReader::new(read_half);
            loop {
                match reader.read::<IpcResponse>().await {
                    Ok(Some(resp)) => {
                        if tx.send(resp).is_err() {
                            break; // receiver dropped
                        }
                    }
                    Ok(None) => break, // EOF
                    Err(e) => {
                        eprintln!("ipc read error: {e}");
                        // Continue reading — don't kill the reader on a single bad message
                    }
                }
            }
        });

        Ok((
            Self {
                writer,
                _daemon: daemon,
            },
            rx,
        ))
    }

    pub async fn send(&mut self, req: &IpcRequest) -> anyhow::Result<()> {
        self.writer.write(req).await?;
        Ok(())
    }
}

/// Find the bozod binary: look next to our own binary first (app bundle),
/// then fall back to PATH.
fn find_daemon_binary() -> anyhow::Result<PathBuf> {
    // Inside an app bundle: Contents/MacOS/bozo and Contents/MacOS/bozod
    if let Ok(exe) = std::env::current_exe() {
        let sibling = exe.with_file_name("bozod");
        if sibling.exists() {
            return Ok(sibling);
        }
    }

    // Fall back to PATH
    which::which("bozod")
        .map_err(|_| anyhow::anyhow!("bozod not found — is it built and in PATH?"))
}

fn spawn_daemon() -> anyhow::Result<Child> {
    let bin = find_daemon_binary()?;
    let child = Command::new(&bin)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .kill_on_drop(false)
        .spawn()?;
    Ok(child)
}

async fn wait_for_socket() -> anyhow::Result<UnixStream> {
    let deadline = tokio::time::Instant::now() + DAEMON_STARTUP_TIMEOUT;
    loop {
        match UnixStream::connect(SOCKET_PATH).await {
            Ok(stream) => return Ok(stream),
            Err(_) if tokio::time::Instant::now() < deadline => {
                tokio::time::sleep(DAEMON_POLL_INTERVAL).await;
            }
            Err(e) => {
                return Err(anyhow::anyhow!(
                    "bozod did not start within {}s: {}",
                    DAEMON_STARTUP_TIMEOUT.as_secs(),
                    e
                ));
            }
        }
    }
}
