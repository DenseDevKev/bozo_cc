use bozo_proto::bmap::packet::BmapPacket;
use bozo_proto::ipc::message::StateUpdate;

/// Internal daemon events distributed via broadcast channel.
#[derive(Debug, Clone)]
pub enum DaemonEvent {
    Connected,
    Disconnected,
    PacketReceived(BmapPacket),
    /// Parsed state change, ready to push to IPC clients.
    StateUpdated(StateUpdate),
}
