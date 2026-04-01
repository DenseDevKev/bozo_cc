//! BMAP protocol library for Bose QC Ultra headphones over BLE.
//!
//! This crate provides encoding/decoding for the Bose Message Access Protocol (BMAP),
//! BLE segmentation/reassembly, typed message builders and parsers for headphone control,
//! and IPC types for daemon-client communication.
//!
//! # Modules
//!
//! - [`bmap`] — Packet codec, BLE segmentation, and protocol enums
//! - [`protocol`] — Typed builders/parsers for battery, audio modes, noise cancellation, etc.
//! - [`ipc`] — Request/response types for daemon-client communication over Unix sockets

pub mod bmap;
pub mod ipc;
pub mod protocol;
