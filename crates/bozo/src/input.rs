use crossterm::event::{KeyCode, KeyEvent};

use crate::app::{App, Confirm};

pub async fn handle_key(app: &mut App, key: KeyEvent) {
    // Confirmation dialog takes priority
    if let Some(confirm) = app.confirm {
        match key.code {
            KeyCode::Char('y') | KeyCode::Char('Y') => {
                app.confirm = None;
                match confirm {
                    Confirm::PowerOff => app.power_off().await,
                }
            }
            KeyCode::Char('n') | KeyCode::Char('N') | KeyCode::Esc => {
                app.confirm = None;
            }
            _ => {}
        }
        return;
    }

    match key.code {
        KeyCode::Char('q') | KeyCode::Char('Q') => app.should_quit = true,
        KeyCode::Tab | KeyCode::BackTab => app.focus = app.focus.next(),
        KeyCode::Char('r') | KeyCode::Char('R') => app.reconnect().await,
        KeyCode::Char('p') | KeyCode::Char('P') => app.confirm = Some(Confirm::PowerOff),

        // Audio mode controls
        KeyCode::Char('+') | KeyCode::Char('=') | KeyCode::Right => {
            app.audio_mode_adjust(1).await
        }
        KeyCode::Char('-') | KeyCode::Left => app.audio_mode_adjust(-1).await,

        // Standby timer
        KeyCode::Char('t') | KeyCode::Char('T') => app.standby_cycle().await,

        _ => {}
    }
}
