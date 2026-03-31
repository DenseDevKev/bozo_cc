mod app;
mod client;
mod input;
mod ui;

use std::io;
use std::time::Duration;

use crossterm::{
    event::{self, Event},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};

use app::App;
use client::IpcClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    eprintln!("Connecting to bozod...");
    let (client, ipc_rx) = match IpcClient::connect().await {
        Ok(pair) => pair,
        Err(e) => {
            eprintln!("Failed to connect to bozod: {e}");
            std::process::exit(1);
        }
    };

    let mut app = App::new(client, ipc_rx);

    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let result = run_loop(&mut terminal, &mut app).await;

    // Restore terminal
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    result
}

async fn run_loop(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
) -> anyhow::Result<()> {
    loop {
        // Drain IPC updates
        app.poll_ipc();

        // Draw
        terminal.draw(|f| ui::draw(f, app))?;

        // Poll for input (non-blocking with short timeout so we stay responsive to IPC)
        if event::poll(Duration::from_millis(50))? {
            if let Event::Key(key) = event::read()? {
                input::handle_key(app, key).await;
            }
        }

        if app.should_quit {
            return Ok(());
        }
    }
}
