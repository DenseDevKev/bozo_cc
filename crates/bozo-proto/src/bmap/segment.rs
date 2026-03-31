/// Maximum data bytes per BLE segment (excluding the 1-byte header).
const SEGMENT_DATA_SIZE: usize = 19;

/// Segments a BMAP packet into BLE-sized chunks.
///
/// Each segment is 20 bytes: 1-byte header + up to 19 bytes of data.
/// Header byte: (max_segment_index << 4) | current_segment_index.
/// A single-segment packet has header 0x00.
pub fn segment(data: &[u8]) -> Vec<Vec<u8>> {
    if data.is_empty() {
        return vec![vec![0x00]];
    }

    let full_segments = data.len() / SEGMENT_DATA_SIZE;
    let remainder = data.len() % SEGMENT_DATA_SIZE;
    let total_segments = full_segments + if remainder > 0 { 1 } else { 0 };
    let max_index = (total_segments - 1) as u8;

    let mut segments = Vec::with_capacity(total_segments);
    let mut offset = 0;

    for i in 0..total_segments {
        let chunk_size = if i < full_segments {
            SEGMENT_DATA_SIZE
        } else {
            remainder
        };

        let mut seg = Vec::with_capacity(1 + chunk_size);
        seg.push((max_index << 4) | (i as u8));
        seg.extend_from_slice(&data[offset..offset + chunk_size]);
        segments.push(seg);

        offset += chunk_size;
    }

    segments
}

/// Check if a segment is the last one (or a single unsegmented packet).
pub fn is_last_segment(segment: &[u8]) -> bool {
    if segment.is_empty() {
        return true;
    }
    let header = segment[0];
    header == 0 || ((header >> 4) & 0x0F) == (header & 0x0F)
}

/// Reassembles segmented BLE data back into the original packet bytes.
#[derive(Debug, Default)]
pub struct Reassembler {
    segments: Vec<Vec<u8>>,
    expected_count: Option<usize>,
}

impl Reassembler {
    pub fn new() -> Self {
        Self::default()
    }

    /// Feed a segment. Returns `Some(data)` when all segments received, `None` if more are expected.
    pub fn feed(&mut self, segment: &[u8]) -> Result<Option<Vec<u8>>, SegmentError> {
        if segment.is_empty() {
            return Err(SegmentError::EmptySegment);
        }

        let header = segment[0];
        let max_index = ((header >> 4) & 0x0F) as usize;
        let current_index = (header & 0x0F) as usize;
        let expected_count = max_index + 1;

        // Single unsegmented packet
        if header == 0x00 {
            let data = segment[1..].to_vec();
            self.reset();
            return Ok(Some(data));
        }

        // Validate consistency
        if let Some(prev) = self.expected_count {
            if prev != expected_count {
                self.reset();
                return Err(SegmentError::InconsistentMaxIndex);
            }
        }
        self.expected_count = Some(expected_count);

        if current_index > max_index {
            self.reset();
            return Err(SegmentError::IndexOutOfRange {
                current: current_index,
                max: max_index,
            });
        }

        // Store data (without header byte)
        if self.segments.is_empty() {
            self.segments.resize(expected_count, Vec::new());
        }
        self.segments[current_index] = segment[1..].to_vec();

        // Check if complete
        if is_last_segment(segment)
            && self.segments.iter().all(|s| !s.is_empty())
        {
            let data: Vec<u8> = self.segments.iter().flat_map(|s| s.iter().copied()).collect();
            self.reset();
            Ok(Some(data))
        } else {
            Ok(None)
        }
    }

    fn reset(&mut self) {
        self.segments.clear();
        self.expected_count = None;
    }
}

#[derive(Debug, thiserror::Error)]
pub enum SegmentError {
    #[error("empty segment")]
    EmptySegment,
    #[error("inconsistent max segment index across segments")]
    InconsistentMaxIndex,
    #[error("segment index {current} exceeds max {max}")]
    IndexOutOfRange { current: usize, max: usize },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn single_small_packet() {
        let data = vec![0x01, 0x05, 0x02, 0x02, 0x05, 0x01]; // 6 bytes, fits in one segment
        let segments = segment(&data);
        assert_eq!(segments.len(), 1);
        assert_eq!(segments[0][0], 0x00); // header: max=0, current=0
        assert_eq!(&segments[0][1..], &data);
    }

    #[test]
    fn exact_19_bytes() {
        let data = vec![0xAA; 19];
        let segments = segment(&data);
        assert_eq!(segments.len(), 1);
        assert_eq!(segments[0].len(), 20);
        assert_eq!(segments[0][0], 0x00);
    }

    #[test]
    fn two_segments() {
        let data = vec![0xBB; 25]; // 19 + 6
        let segments = segment(&data);
        assert_eq!(segments.len(), 2);
        // max_index = 1
        assert_eq!(segments[0][0], 0x10); // (1 << 4) | 0
        assert_eq!(segments[0].len(), 20);
        assert_eq!(segments[1][0], 0x11); // (1 << 4) | 1
        assert_eq!(segments[1].len(), 7); // 1 header + 6 data
    }

    #[test]
    fn three_segments() {
        let data = vec![0xCC; 40]; // 19 + 19 + 2
        let segments = segment(&data);
        assert_eq!(segments.len(), 3);
        assert_eq!(segments[0][0], 0x20); // (2 << 4) | 0
        assert_eq!(segments[1][0], 0x21); // (2 << 4) | 1
        assert_eq!(segments[2][0], 0x22); // (2 << 4) | 2
        assert_eq!(segments[2].len(), 3); // 1 header + 2 data
    }

    #[test]
    fn reassemble_single() {
        let data = vec![0x01, 0x02, 0x03];
        let segments = segment(&data);
        let mut r = Reassembler::new();
        let result = r.feed(&segments[0]).unwrap();
        assert_eq!(result, Some(data));
    }

    #[test]
    fn reassemble_multi() {
        let data = vec![0xDD; 30]; // 19 + 11
        let segments = segment(&data);
        assert_eq!(segments.len(), 2);

        let mut r = Reassembler::new();
        assert_eq!(r.feed(&segments[0]).unwrap(), None);
        let result = r.feed(&segments[1]).unwrap().unwrap();
        assert_eq!(result, data);
    }

    #[test]
    fn roundtrip_large() {
        let data: Vec<u8> = (0..=255).collect(); // 256 bytes
        let segments = segment(&data);
        // 256 / 19 = 13 full + 9 remainder = 14 segments
        assert_eq!(segments.len(), 14);

        let mut r = Reassembler::new();
        for (i, seg) in segments.iter().enumerate() {
            let result = r.feed(seg).unwrap();
            if i < segments.len() - 1 {
                assert_eq!(result, None);
            } else {
                assert_eq!(result, Some(data.clone()));
            }
        }
    }

    #[test]
    fn is_last_segment_check() {
        assert!(is_last_segment(&[0x00, 0x01, 0x02])); // single
        assert!(is_last_segment(&[0x11, 0x01, 0x02])); // (1<<4)|1 = last of 2
        assert!(!is_last_segment(&[0x10, 0x01, 0x02])); // (1<<4)|0 = first of 2
        assert!(is_last_segment(&[0x22, 0x01])); // (2<<4)|2 = last of 3
    }
}
