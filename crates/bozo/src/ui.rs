use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, Paragraph},
    Frame,
};

use crate::app::{App, Confirm, Focus};

pub fn draw(f: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // header
            Constraint::Length(3), // battery
            Constraint::Length(3), // CNC
            Constraint::Length(3), // standby timer
            Constraint::Min(1),   // status/spacer
            Constraint::Length(1), // keybinds
        ])
        .split(f.area());

    draw_header(f, app, chunks[0]);
    draw_battery(f, app, chunks[1]);
    draw_audio_mode(f, app, chunks[2]);
    draw_standby(f, app, chunks[3]);
    draw_status(f, app, chunks[4]);
    draw_keybinds(f, app, chunks[5]);
}

fn draw_header(f: &mut Frame, app: &App, area: Rect) {
    let name = app
        .state
        .product_name
        .as_deref()
        .unwrap_or("(unknown device)");

    let conn_style = if app.state.connected {
        Style::default().fg(Color::Green)
    } else {
        Style::default().fg(Color::Red)
    };
    let conn_text = if app.state.connected {
        "connected"
    } else {
        "disconnected"
    };

    let text = Line::from(vec![
        Span::styled(name, Style::default().add_modifier(Modifier::BOLD)),
        Span::raw("  "),
        Span::styled(conn_text, conn_style),
    ]);

    let block = Block::default().borders(Borders::ALL).title("bozo");
    let paragraph = Paragraph::new(text).block(block);
    f.render_widget(paragraph, area);
}

fn draw_battery(f: &mut Frame, app: &App, area: Rect) {
    let (pct, label) = if let Some(info) = app.state.battery.first() {
        let remaining = info
            .remaining_minutes
            .map(|m| format!(" ({m} min remaining)"))
            .unwrap_or_default();
        (info.percentage as f64 / 100.0, format!("{}%{}", info.percentage, remaining))
    } else {
        (0.0, "-- %".into())
    };

    let color = match (pct * 100.0) as u8 {
        0..=15 => Color::Red,
        16..=30 => Color::Yellow,
        _ => Color::Green,
    };

    let gauge = Gauge::default()
        .block(Block::default().borders(Borders::ALL).title("Battery"))
        .gauge_style(Style::default().fg(color))
        .ratio(pct.clamp(0.0, 1.0))
        .label(label);
    f.render_widget(gauge, area);
}

fn draw_audio_mode(f: &mut Frame, app: &App, area: Rect) {
    let focused = app.focus == Focus::AudioMode;
    let border_style = if focused {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default()
    };

    let block = Block::default()
        .borders(Borders::ALL)
        .title("Audio Mode")
        .border_style(border_style);

    let current_idx = app.state.audio_mode_index;

    if app.state.audio_modes.is_empty() {
        let label = match current_idx {
            Some(idx) => format!("Mode {idx}"),
            None => "--".to_string(),
        };
        let p = Paragraph::new(label).block(block);
        f.render_widget(p, area);
        return;
    }

    let spans: Vec<Span> = app
        .state
        .audio_modes
        .iter()
        .enumerate()
        .flat_map(|(i, mode)| {
            let is_active = current_idx == Some(mode.mode_index);
            let style = if is_active {
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::DarkGray)
            };
            let mut v = vec![Span::styled(&mode.name, style)];
            if i < app.state.audio_modes.len() - 1 {
                v.push(Span::styled(" | ", Style::default().fg(Color::DarkGray)));
            }
            v
        })
        .collect();

    let p = Paragraph::new(Line::from(spans)).block(block);
    f.render_widget(p, area);
}

fn draw_standby(f: &mut Frame, app: &App, area: Rect) {
    let focused = app.focus == Focus::StandbyTimer;
    let border_style = if focused {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default()
    };

    let block = Block::default()
        .borders(Borders::ALL)
        .title("Standby Timer")
        .border_style(border_style);

    let label = match app.state.standby_timer_minutes {
        Some(0) => "Never".to_string(),
        Some(m) => format!("{m} min"),
        None => "--".to_string(),
    };

    let p = Paragraph::new(label).block(block);
    f.render_widget(p, area);
}

fn draw_status(f: &mut Frame, app: &App, area: Rect) {
    if let Some(Confirm::PowerOff) = app.confirm {
        let text = Line::from(vec![
            Span::styled("Power off? ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::raw("y/n"),
        ]);
        let p = Paragraph::new(text).block(Block::default().borders(Borders::ALL).title("Confirm"));
        f.render_widget(p, area);
        return;
    }

    if let Some(msg) = &app.status_msg {
        let p = Paragraph::new(msg.as_str())
            .block(Block::default().borders(Borders::ALL));
        f.render_widget(p, area);
    }
}

fn draw_keybinds(f: &mut Frame, app: &App, area: Rect) {
    let binds = if app.confirm.is_some() {
        vec![
            ("y", "confirm"),
            ("n/Esc", "cancel"),
        ]
    } else {
        vec![
            ("Tab", "focus"),
            ("+/-", "mode"),
            ("t", "standby"),
            ("p", "power off"),
            ("r", "reconnect"),
            ("q", "quit"),
        ]
    };

    let spans: Vec<Span> = binds
        .iter()
        .enumerate()
        .flat_map(|(i, (key, desc))| {
            let mut v = vec![
                Span::styled(*key, Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
                Span::raw(format!(" {desc}")),
            ];
            if i < binds.len() - 1 {
                v.push(Span::styled(" | ", Style::default().fg(Color::DarkGray)));
            }
            v
        })
        .collect();

    f.render_widget(Paragraph::new(Line::from(spans)), area);
}
