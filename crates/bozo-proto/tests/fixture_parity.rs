use bozo_proto::bmap::packet::BmapPacket;
use serde::Deserialize;
use std::{fs, path::PathBuf};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    schema_version: u8,
    fixtures: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Fixture {
    name: String,
    direction: String,
    wire_hex: String,
    expected: ExpectedPacket,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExpectedPacket {
    function_block: u8,
    function: u8,
    operator: u8,
    payload_hex: String,
}

fn decode_hex(value: &str) -> Result<Vec<u8>, String> {
    if value.len() % 2 != 0 {
        return Err(format!("hex string has odd length: {}", value.len()));
    }

    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let text = std::str::from_utf8(pair).map_err(|error| error.to_string())?;
            u8::from_str_radix(text, 16)
                .map_err(|error| format!("invalid hex byte {text:?}: {error}"))
        })
        .collect()
}

fn encode_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[test]
fn shared_fixtures_decode_with_rust_codec() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/bmap");
    let manifest: Manifest = serde_json::from_slice(
        &fs::read(root.join("manifest.json")).expect("read fixture manifest"),
    )
    .expect("decode fixture manifest");

    assert_eq!(manifest.schema_version, 1);
    assert!(!manifest.fixtures.is_empty());

    for filename in manifest.fixtures {
        let fixture: Fixture = serde_json::from_slice(
            &fs::read(root.join(&filename)).unwrap_or_else(|error| {
                panic!("read fixture {filename}: {error}")
            }),
        )
        .unwrap_or_else(|error| panic!("decode fixture {filename}: {error}"));

        assert!(
            matches!(fixture.direction.as_str(), "request" | "response"),
            "{} has invalid direction {}",
            fixture.name,
            fixture.direction
        );

        let bytes = decode_hex(&fixture.wire_hex)
            .unwrap_or_else(|error| panic!("{} wire hex: {error}", fixture.name));
        let packet = BmapPacket::from_bytes(&bytes)
            .unwrap_or_else(|error| panic!("{} packet decode: {error}", fixture.name));

        assert_eq!(u8::from(packet.function_block), fixture.expected.function_block, "{} function block", fixture.name);
        assert_eq!(packet.function, fixture.expected.function, "{} function", fixture.name);
        assert_eq!(u8::from(packet.operator), fixture.expected.operator, "{} operator", fixture.name);
        assert_eq!(encode_hex(&packet.payload), fixture.expected.payload_hex.to_lowercase(), "{} payload", fixture.name);
        assert_eq!(packet.to_bytes(), bytes, "{} round trip", fixture.name);
    }
}

#[test]
fn hex_decoder_rejects_invalid_input() {
    assert!(decode_hex("ABC").is_err());
    assert!(decode_hex("0G").is_err());
}
