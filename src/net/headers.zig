const packet_meta = @import("packet_meta.zig");

pub const BatchHeader = struct {
    salt: u64 = 0,
    num_packets: u16,
    size: u16 = 0,

    id: u16 = 0,

    reliable: bool = false,
    last_packet_id: u16 = 0,
    ack_bits: u32 = 0,
};

pub const Header = struct {
    kind: packet_meta.MessageKind,
    id: u16,
    reliable: bool,
};
