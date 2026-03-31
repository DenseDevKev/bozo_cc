use serde::{de::DeserializeOwned, Serialize};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

/// Reads JSON-lines messages from an async reader.
pub struct IpcReader<R> {
    reader: BufReader<R>,
    line_buf: String,
}

impl<R: tokio::io::AsyncRead + Unpin> IpcReader<R> {
    pub fn new(reader: R) -> Self {
        Self {
            reader: BufReader::new(reader),
            line_buf: String::new(),
        }
    }

    /// Read the next message. Returns `None` on EOF.
    pub async fn read<T: DeserializeOwned>(&mut self) -> Result<Option<T>, IpcTransportError> {
        self.line_buf.clear();
        let n = self
            .reader
            .read_line(&mut self.line_buf)
            .await
            .map_err(IpcTransportError::Io)?;

        if n == 0 {
            return Ok(None); // EOF
        }

        let msg =
            serde_json::from_str(self.line_buf.trim()).map_err(IpcTransportError::Deserialize)?;
        Ok(Some(msg))
    }
}

/// Writes JSON-lines messages to an async writer.
pub struct IpcWriter<W> {
    writer: W,
}

impl<W: tokio::io::AsyncWrite + Unpin> IpcWriter<W> {
    pub fn new(writer: W) -> Self {
        Self { writer }
    }

    /// Write a message as a JSON line.
    pub async fn write<T: Serialize>(&mut self, msg: &T) -> Result<(), IpcTransportError> {
        let mut json = serde_json::to_string(msg).map_err(IpcTransportError::Serialize)?;
        json.push('\n');
        self.writer
            .write_all(json.as_bytes())
            .await
            .map_err(IpcTransportError::Io)?;
        self.writer.flush().await.map_err(IpcTransportError::Io)?;
        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum IpcTransportError {
    #[error("io error: {0}")]
    Io(std::io::Error),
    #[error("deserialize error: {0}")]
    Deserialize(serde_json::Error),
    #[error("serialize error: {0}")]
    Serialize(serde_json::Error),
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ipc::message::IpcRequest;

    #[tokio::test]
    async fn roundtrip_over_pipe() {
        let (client, server) = tokio::io::duplex(1024);
        let (server_read, server_write) = tokio::io::split(server);
        let (client_read, client_write) = tokio::io::split(client);

        let mut writer = IpcWriter::new(client_write);
        let mut reader = IpcReader::new(server_read);

        // Write from client
        writer.write(&IpcRequest::GetState).await.unwrap();
        writer
            .write(&IpcRequest::SetCnc {
                level: 7,
                enabled: true,
            })
            .await
            .unwrap();

        // Read on server
        let msg1: IpcRequest = reader.read().await.unwrap().unwrap();
        assert!(matches!(msg1, IpcRequest::GetState));

        let msg2: IpcRequest = reader.read().await.unwrap().unwrap();
        match msg2 {
            IpcRequest::SetCnc { level, enabled } => {
                assert_eq!(level, 7);
                assert!(enabled);
            }
            _ => panic!("expected SetCnc"),
        }

        // Also test server -> client direction
        let mut server_writer = IpcWriter::new(server_write);
        let mut client_reader = IpcReader::new(client_read);

        use crate::ipc::message::IpcResponse;
        server_writer.write(&IpcResponse::Ok).await.unwrap();
        let resp: IpcResponse = client_reader.read().await.unwrap().unwrap();
        assert!(matches!(resp, IpcResponse::Ok));
    }
}
