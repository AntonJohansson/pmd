const std = @import("std");
const res = @import("res.zig");
const gs = @import("common.zig");
const goosepack = gs.goosepack;

const cache_len = 64;
pub const ResourceCache = struct {
    indices: [cache_len]?usize = .{null} ** cache_len,
    resources: [cache_len]goosepack.Resource = undefined,
    pack: *goosepack.Pack = undefined,
    mutex: gs.Mutex = .{},
    last_evicted: usize = 0,
    eviction_list: gs.ArrayRealloc(struct {
        id: usize,
        resource: goosepack.Resource,
    }, 16) = .{}
};

pub fn load(cache: *ResourceCache, id: usize) goosepack.Resource {
    cache.mutex.lock();
    defer cache.mutex.unlock();

    for (cache.indices, 0..) |ind, i| {
        if (ind == id) {
            return cache.resources[i];
        }
    }

    var free_index: ?usize = null;
    for (cache.indices, 0..) |ind, i| {
        if (ind == null) {
            free_index = i;
        }
    }

    if (free_index == null) {
        cache.eviction_list.append(.{
            .id = cache.indices[cache.last_evicted].?,
            .resource = cache.resources[cache.last_evicted],
        });
        free_index = cache.last_evicted;
        cache.last_evicted = (cache.last_evicted + 1) % cache_len;
    }

    const resource = goosepack.getResource(cache.pack, id);
    cache.indices[free_index.?] = id;
    cache.resources[free_index.?] = resource;

    return resource;
}

pub fn free_evictions(cache: *ResourceCache) void {
    for (cache.eviction_list.slice()) |e| {
        goosepack.freeResource(cache.pack, &e.resource, e.id);
    }
    cache.eviction_list.reset();
}


