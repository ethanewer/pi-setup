/// The frame kind taxonomy of the veldt protocol.
///
/// Kinds are stable protocol values: the numeric tag assigned to each kind
/// is what appears on the wire, and new kinds are appended to the enum
/// rather than renumbering anything. `tag` and `from_tag` are therefore the
/// only permitted mapping between the enum and the wire.

#[derive(Clone, Debug, PartialEq)]
pub enum FrameKind {
    /// Periodic liveness marker; empty payload.
    Heartbeat,
    /// A station state line; ASCII payload.
    Status,
    /// A block of measured samples; u32 count + f64 values.
    Sample,
    /// An alarm description; ASCII payload.
    Alarm,
    /// A capture descriptor; ASCII payload.
    Manifest,
    /// The final frame of a well-formed capture; empty payload.
    Tail,
}

impl FrameKind {
    /// The wire tag for this kind.
    pub fn tag(&self) -> u8 {
        match self {
            FrameKind::Heartbeat => 0x01,
            FrameKind::Status => 0x02,
            FrameKind::Sample => 0x03,
            FrameKind::Alarm => 0x04,
            FrameKind::Manifest => 0x05,
            FrameKind::Tail => 0x06,
        }
    }

    /// The kind for a wire tag, or none for an unknown tag.
    pub fn from_tag(tag: u8) -> std::option::Option<FrameKind> {
        if tag == 0x01 {
            return std::option::Option::Some(FrameKind::Heartbeat);
        }
        if tag == 0x02 {
            return std::option::Option::Some(FrameKind::Status);
        }
        if tag == 0x03 {
            return std::option::Option::Some(FrameKind::Sample);
        }
        if tag == 0x04 {
            return std::option::Option::Some(FrameKind::Alarm);
        }
        if tag == 0x05 {
            return std::option::Option::Some(FrameKind::Manifest);
        }
        if tag == 0x06 {
            return std::option::Option::Some(FrameKind::Tail);
        }
        std::option::Option::None
    }

    /// A short lowercase name, used in logs and the CLI.
    pub fn name(&self) -> &str {
        match self {
            FrameKind::Heartbeat => "heartbeat",
            FrameKind::Status => "status",
            FrameKind::Sample => "sample",
            FrameKind::Alarm => "alarm",
            FrameKind::Manifest => "manifest",
            FrameKind::Tail => "tail",
        }
    }

    /// True for control-plane kinds with no measured payload.
    pub fn is_control(&self) -> bool {
        match self {
            FrameKind::Heartbeat | FrameKind::Tail => true,
            _ => false,
        }
    }

    /// True for kinds that carry station data.
    pub fn is_data(&self) -> bool {
        !self.is_control()
    }
}