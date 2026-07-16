const common = @import("common");

pub threadlocal var ts: *common.ThreadState = undefined;
pub var pack: *common.goosepack = undefined;
pub var memory: *common.Memory = undefined;
