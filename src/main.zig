const std = @import("std");
const Order = std.math.Order;
const sfml = @cImport({
    @cInclude("SFML/Graphics.h");
    @cInclude("SFML/Window.h");
    @cInclude("SFML/System.h");
});

const CELL_SIZE = 30;
const MAZE_WIDTH = 25;
const MAZE_HEIGHT = 20;
const WINDOW_WIDTH = MAZE_WIDTH * CELL_SIZE;
const WINDOW_HEIGHT = MAZE_HEIGHT * CELL_SIZE;

const Cell = struct {
    x: usize,
    y: usize,
    walls: [4]bool, // top, right, bottom, left
    visited: bool,

    fn init(x: usize, y: usize) Cell {
        return .{
            .x = x,
            .y = y,
            .walls = [_]bool{true} ** 4,
            .visited = false,
        };
    }
};

const Position = struct {
    x: usize,
    y: usize,

    pub fn hash(self: Position) u64 {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, self.x);
        std.hash.autoHash(&hasher, self.y);
        return hasher.final();
    }

    pub fn eql(a: Position, b: Position) bool {
        return a.x == b.x and a.y == b.y;
    }
};

const Maze = struct {
    cells: [][]Cell,
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,

    fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Maze {
        const cells = try allocator.alloc([]Cell, height);
        for (cells, 0..) |*row, y| {
            row.* = try allocator.alloc(Cell, width);
            for (row.*, 0..) |*cell, x| {
                cell.* = Cell.init(x, y);
            }
        }
        return .{
            .cells = cells,
            .allocator = allocator,
            .width = width,
            .height = height,
        };
    }

    fn deinit(self: *Maze) void {
        for (self.cells) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.cells);
    }

    fn generate(self: *Maze, random: std.Random) !void {
        var stack: std.ArrayList(Position) = .empty;
        defer stack.deinit(self.allocator);

        // Start at (0, 0)
        try stack.append(self.allocator, .{ .x = 0, .y = 0 });
        self.cells[0][0].visited = true;

        while (stack.items.len > 0) {
            const current = stack.items[stack.items.len - 1];
            var neighbors = try self.getUnvisitedNeighbors(current.x, current.y, self.allocator);
            defer neighbors.deinit(self.allocator);

            if (neighbors.items.len > 0) {
                const next = neighbors.items[random.intRangeAtMost(usize, 0, neighbors.items.len - 1)];

                // Remove walls between current and next
                self.removeWalls(current.x, current.y, next.x, next.y);

                self.cells[next.y][next.x].visited = true;
                try stack.append(self.allocator, .{ .x = next.x, .y = next.y });
            } else {
                _ = stack.pop();
            }
        }
    }

    fn getUnvisitedNeighbors(self: *Maze, x: usize, y: usize, allocator: std.mem.Allocator) !std.ArrayList(Position) {
        var neighbors: std.ArrayList(Position) = .empty;

        // Top
        if (y > 0 and !self.cells[y - 1][x].visited) {
            try neighbors.append(allocator, .{ .x = x, .y = y - 1 });
        }
        // Right
        if (x < self.width - 1 and !self.cells[y][x + 1].visited) {
            try neighbors.append(allocator, .{ .x = x + 1, .y = y });
        }
        // Bottom
        if (y < self.height - 1 and !self.cells[y + 1][x].visited) {
            try neighbors.append(allocator, .{ .x = x, .y = y + 1 });
        }
        // Left
        if (x > 0 and !self.cells[y][x - 1].visited) {
            try neighbors.append(allocator, .{ .x = x - 1, .y = y });
        }

        return neighbors;
    }

    fn getAccessibleNeighbors(self: *Maze, x: usize, y: usize, allocator: std.mem.Allocator) !std.ArrayList(Position) {
        var neighbors: std.ArrayList(Position) = .empty;
        const cell = self.cells[y][x];

        // Top
        if (y > 0 and !cell.walls[0]) {
            try neighbors.append(allocator, .{ .x = x, .y = y - 1 });
        }
        // Right
        if (x < self.width - 1 and !cell.walls[1]) {
            try neighbors.append(allocator, .{ .x = x + 1, .y = y });
        }
        // Bottom
        if (y < self.height - 1 and !cell.walls[2]) {
            try neighbors.append(allocator, .{ .x = x, .y = y + 1 });
        }
        // Left
        if (x > 0 and !cell.walls[3]) {
            try neighbors.append(allocator, .{ .x = x - 1, .y = y });
        }

        return neighbors;
    }

    fn removeWalls(self: *Maze, x1: usize, y1: usize, x2: usize, y2: usize) void {
        if (x1 == x2) {
            if (y1 > y2) {
                // Moving up
                self.cells[y1][x1].walls[0] = false; // top
                self.cells[y2][x2].walls[2] = false; // bottom
            } else {
                // Moving down
                self.cells[y1][x1].walls[2] = false; // bottom
                self.cells[y2][x2].walls[0] = false; // top
            }
        } else {
            if (x1 > x2) {
                // Moving left
                self.cells[y1][x1].walls[3] = false; // left
                self.cells[y2][x2].walls[1] = false; // right
            } else {
                // Moving right
                self.cells[y1][x1].walls[1] = false; // right
                self.cells[y2][x2].walls[3] = false; // left
            }
        }
    }

    fn draw(self: *Maze, window: *sfml.sfRenderWindow, player_pos: sfml.sfVector2f) void {
        const white = sfml.sfColor{ .r = 255, .g = 255, .b = 255, .a = 255 };

        for (self.cells, 0..) |row, y| {
            for (row, 0..) |cell, x| {
                const px = @as(f32, @floatFromInt(x * CELL_SIZE));
                const py = @as(f32, @floatFromInt(y * CELL_SIZE));

                // Draw walls
                const line = sfml.sfRectangleShape_create();
                defer sfml.sfRectangleShape_destroy(line);
                sfml.sfRectangleShape_setFillColor(line, white);

                // Top wall
                if (cell.walls[0]) {
                    sfml.sfRectangleShape_setSize(line, sfml.sfVector2f{ .x = CELL_SIZE, .y = 2 });
                    sfml.sfRectangleShape_setPosition(line, sfml.sfVector2f{ .x = px, .y = py });
                    sfml.sfRenderWindow_drawRectangleShape(window, line, null);
                }
                // Right wall
                if (cell.walls[1]) {
                    sfml.sfRectangleShape_setSize(line, sfml.sfVector2f{ .x = 2, .y = CELL_SIZE });
                    sfml.sfRectangleShape_setPosition(line, sfml.sfVector2f{ .x = px + CELL_SIZE, .y = py });
                    sfml.sfRenderWindow_drawRectangleShape(window, line, null);
                }
                // Bottom wall
                if (cell.walls[2]) {
                    sfml.sfRectangleShape_setSize(line, sfml.sfVector2f{ .x = CELL_SIZE, .y = 2 });
                    sfml.sfRectangleShape_setPosition(line, sfml.sfVector2f{ .x = px, .y = py + CELL_SIZE });
                    sfml.sfRenderWindow_drawRectangleShape(window, line, null);
                }
                // Left wall
                if (cell.walls[3]) {
                    sfml.sfRectangleShape_setSize(line, sfml.sfVector2f{ .x = 2, .y = CELL_SIZE });
                    sfml.sfRectangleShape_setPosition(line, sfml.sfVector2f{ .x = px, .y = py });
                    sfml.sfRenderWindow_drawRectangleShape(window, line, null);
                }
            }
        }

        // Draw start and end markers using images
        const start_texture = sfml.sfTexture_createFromFile("assets/hipo.png", null);
        defer sfml.sfTexture_destroy(start_texture);
        const start_sprite = sfml.sfSprite_create();
        defer sfml.sfSprite_destroy(start_sprite);
        sfml.sfSprite_setTexture(start_sprite, start_texture, 1);

        const start_size = sfml.sfTexture_getSize(start_texture);
        const start_scale = (@as(f32, @floatFromInt(CELL_SIZE)) * 0.8) / @as(f32, @floatFromInt(start_size.x));
        sfml.sfSprite_setScale(start_sprite, sfml.sfVector2f{ .x = start_scale, .y = start_scale });
        sfml.sfSprite_setPosition(start_sprite, player_pos);
        sfml.sfRenderWindow_drawSprite(window, start_sprite, null);

        const end_texture = sfml.sfTexture_createFromFile("assets/ishto.png", null);
        defer sfml.sfTexture_destroy(end_texture);
        const end_sprite = sfml.sfSprite_create();
        defer sfml.sfSprite_destroy(end_sprite);
        sfml.sfSprite_setTexture(end_sprite, end_texture, 1);

        const end_size = sfml.sfTexture_getSize(end_texture);
        const end_scale = (@as(f32, @floatFromInt(CELL_SIZE)) * 0.8) / @as(f32, @floatFromInt(end_size.x));
        sfml.sfSprite_setScale(end_sprite, sfml.sfVector2f{ .x = end_scale, .y = end_scale });
        const end_x = @as(f32, @floatFromInt((self.width - 1) * CELL_SIZE + @as(usize, @intFromFloat(CELL_SIZE * 0.15))));
        const end_y = @as(f32, @floatFromInt((self.height - 1) * CELL_SIZE + @as(usize, @intFromFloat(CELL_SIZE * 0.15))));
        sfml.sfSprite_setPosition(end_sprite, sfml.sfVector2f{ .x = end_x, .y = end_y });
        sfml.sfRenderWindow_drawSprite(window, end_sprite, null);
    }
};

const AStarNode = struct {
    pos: Position,
    f_score: u32,
};

fn compareNodes(context: void, a: AStarNode, b: AStarNode) Order {
    _ = context;
    return std.math.order(a.f_score, b.f_score);
}

const PathfindingAlgorithm = enum {
    BFS,
    AStar,
};

const Pathfinder = struct {
    algorithm: PathfindingAlgorithm,
    allocator: std.mem.Allocator,

    // State for animation
    active: bool,
    found: bool,
    start_pos: Position,
    end_pos: Position,

    // Data structures for algorithms
    queue: std.ArrayList(Position), // For BFS
    open_set: std.PriorityQueue(AStarNode, void, compareNodes), // For A*
    came_from: std.HashMap(Position, Position, std.hash_map.AutoContext(Position), 80),
    g_score: std.HashMap(Position, u32, std.hash_map.AutoContext(Position), 80), // For A*
    visited_map: std.HashMap(Position, void, std.hash_map.AutoContext(Position), 80),

    // For drawing
    path: std.ArrayList(Position),

    fn init(allocator: std.mem.Allocator, algorithm: PathfindingAlgorithm, start_pos: Position, end_pos: Position) Pathfinder {
        return .{
            .algorithm = algorithm,
            .allocator = allocator,
            .active = false,
            .found = false,
            .start_pos = start_pos,
            .end_pos = end_pos,
            .queue = .{},
            .open_set = std.PriorityQueue(AStarNode, void, compareNodes).init(allocator, {}),
            .came_from = std.HashMap(Position, Position, std.hash_map.AutoContext(Position), 80).init(allocator),
            .g_score = std.HashMap(Position, u32, std.hash_map.AutoContext(Position), 80).init(allocator),
            .visited_map = std.HashMap(Position, void, std.hash_map.AutoContext(Position), 80).init(allocator),
            .path = .{},
        };
    }

    fn deinit(self: *Pathfinder) void {
        self.queue.deinit(self.allocator);
        self.open_set.deinit();
        self.came_from.deinit();
        self.g_score.deinit();
        self.visited_map.deinit();
        self.path.deinit(self.allocator);
    }

    fn start(self: *Pathfinder) !void {
        self.active = true;
        self.found = false;
        self.queue.clearRetainingCapacity();
        self.open_set.clearRetainingCapacity();
        self.came_from.clearRetainingCapacity();
        self.g_score.clearRetainingCapacity();
        self.visited_map.clearRetainingCapacity();
        self.path.clearRetainingCapacity();

        try self.visited_map.put(self.start_pos, {});

        switch (self.algorithm) {
            .BFS => try self.queue.append(self.allocator, self.start_pos),
            .AStar => {
                try self.g_score.put(self.start_pos, 0);
                try self.open_set.add(.{ .pos = self.start_pos, .f_score = self.heuristic(self.start_pos, self.end_pos) });
            },
        }
    }

    fn step(self: *Pathfinder, maze: *Maze) !void {
        if (!self.active or self.found) return;

        switch (self.algorithm) {
            .BFS => try self.bfsStep(maze),
            .AStar => try self.aStarStep(maze),
        }
    }

    fn bfsStep(self: *Pathfinder, maze: *Maze) !void {
        if (self.queue.items.len == 0) {
            self.active = false;
            return;
        }

        const current = self.queue.orderedRemove(0);

        if (current.x == self.end_pos.x and current.y == self.end_pos.y) {
            self.found = true;
            self.active = false;
            // Reconstruct path
            var path_curr = self.end_pos;
            while (path_curr.x != self.start_pos.x or path_curr.y != self.start_pos.y) : (path_curr = self.came_from.get(path_curr).?) {
                try self.path.append(self.allocator, path_curr);
            }
            try self.path.append(self.allocator, self.start_pos);
            std.mem.reverse(Position, self.path.items);
            return;
        }

        var neighbors = try maze.getAccessibleNeighbors(current.x, current.y, self.allocator);
        defer neighbors.deinit(self.allocator);

        for (neighbors.items) |neighbor| {
            if (!self.visited_map.contains(neighbor)) {
                try self.visited_map.put(neighbor, {});
                try self.came_from.put(neighbor, current);
                try self.queue.append(self.allocator, neighbor);
            }
        }
    }

    fn aStarStep(self: *Pathfinder, maze: *Maze) !void {
        if (self.open_set.peek() == null) {
            self.active = false;
            return;
        }

        const current = self.open_set.remove();

        if (current.pos.x == self.end_pos.x and current.pos.y == self.end_pos.y) {
            self.found = true;
            self.active = false;
            // Reconstruct path
            var path_curr = self.end_pos;
            while (path_curr.x != self.start_pos.x or path_curr.y != self.start_pos.y) : (path_curr = self.came_from.get(path_curr).?) {
                try self.path.append(self.allocator, path_curr);
            }
            try self.path.append(self.allocator, self.start_pos);
            std.mem.reverse(Position, self.path.items);
            return;
        }

        var neighbors = try maze.getAccessibleNeighbors(current.pos.x, current.pos.y, self.allocator);
        defer neighbors.deinit(self.allocator);

        for (neighbors.items) |neighbor| {
            const tentative_g_score = self.g_score.get(current.pos).? + 1;
            const existing_g_score = self.g_score.get(neighbor);

            if (existing_g_score == null or tentative_g_score < existing_g_score.?) {
                try self.came_from.put(neighbor, current.pos);
                try self.g_score.put(neighbor, tentative_g_score);
                const f_score = tentative_g_score + self.heuristic(neighbor, self.end_pos);
                try self.open_set.add(.{ .pos = neighbor, .f_score = @intCast(f_score) });
            }
        }
    }


    fn draw(self: *Pathfinder, window: *sfml.sfRenderWindow) void {
        const visited_color = sfml.sfColor{ .r = 128, .g = 128, .b = 128, .a = 255 };
        const path_color = sfml.sfColor{ .r = 0, .g = 255, .b = 0, .a = 255 };

        // Draw visited trail
        var it = self.came_from.iterator();
        while (it.next()) |entry| {
            const from = entry.key_ptr.*;
            const to = entry.value_ptr.*;
            const from_center = sfml.sfVector2f{
                .x = @as(f32, @floatFromInt(from.x * CELL_SIZE)) + CELL_SIZE / 2,
                .y = @as(f32, @floatFromInt(from.y * CELL_SIZE)) + CELL_SIZE / 2,
            };
            const to_center = sfml.sfVector2f{
                .x = @as(f32, @floatFromInt(to.x * CELL_SIZE)) + CELL_SIZE / 2,
                .y = @as(f32, @floatFromInt(to.y * CELL_SIZE)) + CELL_SIZE / 2,
            };
            self.drawLine(window, from_center, to_center, visited_color, 2);
        }

        // Draw final path
        if (self.path.items.len > 1) {
            for (0..self.path.items.len - 1) |i| {
                const from = self.path.items[i];
                const to = self.path.items[i + 1];
                const from_center = sfml.sfVector2f{
                    .x = @as(f32, @floatFromInt(from.x * CELL_SIZE)) + CELL_SIZE / 2,
                    .y = @as(f32, @floatFromInt(from.y * CELL_SIZE)) + CELL_SIZE / 2,
                };
                const to_center = sfml.sfVector2f{
                    .x = @as(f32, @floatFromInt(to.x * CELL_SIZE)) + CELL_SIZE / 2,
                    .y = @as(f32, @floatFromInt(to.y * CELL_SIZE)) + CELL_SIZE / 2,
                };
                self.drawLine(window, from_center, to_center, path_color, 4);
            }
        }
    }

    fn drawLine(self: *Pathfinder, window: *sfml.sfRenderWindow, p1: sfml.sfVector2f, p2: sfml.sfVector2f, color: sfml.sfColor, thickness: f32) void {
        _ = self;
        const line = sfml.sfRectangleShape_create();
        defer sfml.sfRectangleShape_destroy(line);

        const diff = sfml.sfVector2f{ .x = p2.x - p1.x, .y = p2.y - p1.y };
        const length = std.math.sqrt(diff.x * diff.x + diff.y * diff.y);
        const angle = std.math.atan2(diff.y, diff.x) * 180 / std.math.pi;

        sfml.sfRectangleShape_setSize(line, sfml.sfVector2f{ .x = length, .y = thickness });
        sfml.sfRectangleShape_setOrigin(line, sfml.sfVector2f{ .x = 0, .y = thickness / 2 });
        sfml.sfRectangleShape_setPosition(line, p1);
        sfml.sfRectangleShape_setRotation(line, angle);
        sfml.sfRectangleShape_setFillColor(line, color);

        sfml.sfRenderWindow_drawRectangleShape(window, line, null);
    }

    fn heuristic(self: *Pathfinder, a: Position, b: Position) u32 {
        _ = self;
        const dx = if (a.x > b.x) a.x - b.x else b.x - a.x;
        const dy = if (a.y > b.y) a.y - b.y else b.y - a.y;
        return @intCast(dx + dy);
    }
};


fn drawOverlay(window: *sfml.sfRenderWindow, lines: []const []const u8, font: *sfml.sfFont) void {
    const text_color = sfml.sfColor{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const bg_color = sfml.sfColor{ .r = 0, .g = 0, .b = 0, .a = 180 };
    const padding: f32 = 3.0;
    const line_spacing: f32 = 2.0;
    const font_size: u32 = 16;

    // Create text object to measure dimensions
    const text = sfml.sfText_create();
    defer sfml.sfText_destroy(text);
    sfml.sfText_setFont(text, font);
    sfml.sfText_setCharacterSize(text, font_size);

    // Find the widest line and calculate total height
    var max_width: f32 = 0;
    var total_height: f32 = 0;
    for (lines) |line| {
        sfml.sfText_setString(text, line.ptr);
        const bounds = sfml.sfText_getLocalBounds(text);
        if (bounds.width > max_width) {
            max_width = bounds.width;
        }
        total_height += bounds.height + line_spacing;
    }

    // Calculate overlay dimensions and position
    const overlay_width = max_width + padding * 2;
    const overlay_height = total_height + padding * 2;
    const overlay_x = @as(f32, @floatFromInt(WINDOW_WIDTH)) - overlay_width - 10;
    const overlay_y: f32 = 10;

    // // Draw background rectangle
    const bg_rect = sfml.sfRectangleShape_create();
    defer sfml.sfRectangleShape_destroy(bg_rect);
    sfml.sfRectangleShape_setSize(bg_rect, sfml.sfVector2f{ .x = overlay_width, .y = overlay_height });
    sfml.sfRectangleShape_setPosition(bg_rect, sfml.sfVector2f{ .x = overlay_x, .y = overlay_y });
    sfml.sfRectangleShape_setFillColor(bg_rect, bg_color);
    sfml.sfRenderWindow_drawRectangleShape(window, bg_rect, null);

    // Draw text lines with right alignment
    var current_y = overlay_y + padding;
    for (lines) |line| {
        sfml.sfText_setString(text, line.ptr);
        sfml.sfText_setFillColor(text, text_color);

        const bounds = sfml.sfText_getLocalBounds(text);
        const text_x = overlay_x + overlay_width - padding - bounds.width;

        sfml.sfText_setPosition(text, sfml.sfVector2f{ .x = text_x, .y = current_y });
        sfml.sfRenderWindow_drawText(window, text, null);

        current_y += bounds.height + line_spacing;
    }
}

fn drawStats(window: *sfml.sfRenderWindow, font: *sfml.sfFont, pathfinder: ?*Pathfinder, allocator: std.mem.Allocator) !void {
    if (pathfinder == null) return;

    const p = pathfinder.?;
    const text_color = sfml.sfColor{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const bg_color = sfml.sfColor{ .r = 0, .g = 0, .b = 0, .a = 180 };
    const padding: f32 = 3.0;
    const font_size: u32 = 16;

    const algo_str = switch (p.algorithm) {
        .BFS => "BFS",
        .AStar => "A*",
    };

    const visited_count = p.came_from.count();

    var line1_list: std.ArrayList(u8) = .empty;
    defer line1_list.deinit(allocator);
    try std.fmt.format(line1_list.writer(allocator), "Algorithm: {s}", .{algo_str});
    try line1_list.append(allocator, 0);
    const line1_str = line1_list.items;

    var line2_list: std.ArrayList(u8) = .empty;
    defer line2_list.deinit(allocator);
    try std.fmt.format(line2_list.writer(allocator), "Visited: {d}", .{visited_count});
    try line2_list.append(allocator, 0);
    const line2_str = line2_list.items;

    const lines = [_][]const u8{
        line1_str,
        line2_str,
    };

    // Create text object to measure dimensions
    const text = sfml.sfText_create();
    defer sfml.sfText_destroy(text);
    sfml.sfText_setFont(text, font);
    sfml.sfText_setCharacterSize(text, font_size);

    // Find the widest line and calculate total height
    var max_width: f32 = 0;
    var total_height: f32 = 0;
    for (lines) |line| {
        sfml.sfText_setString(text, line.ptr);
        const bounds = sfml.sfText_getLocalBounds(text);
        if (bounds.width > max_width) {
            max_width = bounds.width;
        }
        total_height += bounds.height + 2.0;
    }

    // Calculate overlay dimensions and position
    const overlay_width = max_width + padding * 2;
    const overlay_height = total_height + padding * 2;
    const overlay_x: f32 = 10;
    const overlay_y = @as(f32, @floatFromInt(WINDOW_HEIGHT)) - overlay_height - 10;

    // Draw background rectangle
    const bg_rect = sfml.sfRectangleShape_create();
    defer sfml.sfRectangleShape_destroy(bg_rect);
    sfml.sfRectangleShape_setSize(bg_rect, sfml.sfVector2f{ .x = overlay_width, .y = overlay_height });
    sfml.sfRectangleShape_setPosition(bg_rect, sfml.sfVector2f{ .x = overlay_x, .y = overlay_y });
    sfml.sfRectangleShape_setFillColor(bg_rect, bg_color);
    sfml.sfRenderWindow_drawRectangleShape(window, bg_rect, null);

    // Draw text lines
    var current_y = overlay_y + padding;
    for (lines) |line| {
        sfml.sfText_setString(text, line.ptr);
        sfml.sfText_setFillColor(text, text_color);
        sfml.sfText_setPosition(text, sfml.sfVector2f{ .x = overlay_x + padding, .y = current_y });
        sfml.sfRenderWindow_drawText(window, text, null);
        const bounds = sfml.sfText_getLocalBounds(text);
        current_y += bounds.height + 2.0;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize random number generator
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();

    // Create maze
    var maze = try Maze.init(allocator, MAZE_WIDTH, MAZE_HEIGHT);
    defer maze.deinit();
    try maze.generate(random);

    // Create pathfinder
    var pathfinder: ?*Pathfinder = null;

    // Player animation state
    var sliding = false;
    var player_pos_idx: usize = 0;
    var player_anim_t: f32 = 0.0;
    var player_pos = sfml.sfVector2f{ .x = @as(f32, @floatFromInt(CELL_SIZE)) * 0.15, .y = @as(f32, @floatFromInt(CELL_SIZE)) * 0.15 };

    // Create window
    const mode = sfml.sfVideoMode{ .width = WINDOW_WIDTH, .height = WINDOW_HEIGHT, .bitsPerPixel = 32 };
    const window = sfml.sfRenderWindow_create(
        mode,
        "Maze Generator",
        sfml.sfResize | sfml.sfClose,
        null,
    );
    defer {
        if (pathfinder) |p| {
            p.deinit();
            allocator.destroy(p);
        }
        sfml.sfRenderWindow_destroy(window);
    }

    if (window == null) {
        std.debug.print("Failed to create window\n", .{});
        return error.WindowCreationFailed;
    }

    // Main loop
    var event: sfml.sfEvent = undefined;
    while (sfml.sfRenderWindow_isOpen(window) == 1) {
        while (sfml.sfRenderWindow_pollEvent(window, &event) == 1) {
            if (event.type == sfml.sfEvtClosed) {
                sfml.sfRenderWindow_close(window);
            }
            // Press R to regenerate maze
            if (event.type == sfml.sfEvtKeyPressed and event.key.code == sfml.sfKeyR) {
                if (pathfinder) |p| {
                    p.deinit();
                    allocator.destroy(p);
                    pathfinder = null;
                }
                sliding = false;
                player_pos = sfml.sfVector2f{ .x = @as(f32, @floatFromInt(CELL_SIZE)) * 0.15, .y = @as(f32, @floatFromInt(CELL_SIZE)) * 0.15 };
                // Reset visited flags
                for (maze.cells) |row| {
                    for (row) |*cell| {
                        cell.visited = false;
                        cell.walls = [_]bool{true} ** 4;
                    }
                }
                try maze.generate(random);
            }
            // Press Q to quit
            if (event.type == sfml.sfEvtKeyPressed and event.key.code == sfml.sfKeyQ) {
                sfml.sfRenderWindow_close(window);
            }

            // Pathfinding
            if (event.type == sfml.sfEvtKeyPressed) {
                if (event.key.code == sfml.sfKeyA or event.key.code == sfml.sfKeyB) {
                    if (pathfinder) |p| {
                        p.deinit();
                        allocator.destroy(p);
                    }
                    sliding = false;
                    player_pos_idx = 0;
                    player_anim_t = 0.0;
                    player_pos = sfml.sfVector2f{ .x = @as(f32, @floatFromInt(CELL_SIZE)) * 0.15, .y = @as(f32, @floatFromInt(CELL_SIZE)) * 0.15 };

                    const algo = if (event.key.code == sfml.sfKeyA) PathfindingAlgorithm.AStar else PathfindingAlgorithm.BFS;
                    pathfinder = try allocator.create(Pathfinder);
                    pathfinder.?.* = Pathfinder.init(allocator, algo, .{ .x = 0, .y = 0 }, .{ .x = MAZE_WIDTH - 1, .y = MAZE_HEIGHT - 1 });
                    try pathfinder.?.start();
                }
            }
        }

        if (pathfinder) |p| {
            if (!p.found) {
                try p.step(&maze);
                if (p.found and p.path.items.len > 0) {
                    sliding = true;
                    player_pos_idx = 0;
                    player_anim_t = 0;
                }
            }
        }

        if (sliding and pathfinder != null) {
            const p = pathfinder.?;
            if (player_pos_idx + 1 < p.path.items.len) {
                player_anim_t += 0.1;
                if (player_anim_t >= 1.0) {
                    player_anim_t = 0;
                    player_pos_idx += 1;
                }
            } else {
                sliding = false;
            }

            if (player_pos_idx + 1 < p.path.items.len) {
                const start = p.path.items[player_pos_idx];
                const end = p.path.items[player_pos_idx + 1];
                const start_px = sfml.sfVector2f{
                    .x = @as(f32, @floatFromInt(start.x * CELL_SIZE)) + CELL_SIZE * 0.15,
                    .y = @as(f32, @floatFromInt(start.y * CELL_SIZE)) + CELL_SIZE * 0.15,
                };
                const end_px = sfml.sfVector2f{
                    .x = @as(f32, @floatFromInt(end.x * CELL_SIZE)) + CELL_SIZE * 0.15,
                    .y = @as(f32, @floatFromInt(end.y * CELL_SIZE)) + CELL_SIZE * 0.15,
                };
                player_pos.x = start_px.x + (end_px.x - start_px.x) * player_anim_t;
                player_pos.y = start_px.y + (end_px.y - start_px.y) * player_anim_t;
            }
        }

        sfml.sfRenderWindow_clear(window, sfml.sfColor{ .r = 20, .g = 20, .b = 20, .a = 255 });
        if (pathfinder) |p| {
            p.draw(window.?);
        }
        maze.draw(window.?, player_pos);

        const font = sfml.sfFont_createFromFile("assets/font.ttf");
        if (font == null) {
            std.debug.print("Failed to load font\n", .{});
            return error.FontLoadFailed;
        }
        defer sfml.sfFont_destroy(font);

        const overlay_lines = [_][]const u8{
            "[R]egenerate",
            "[A]*",
            "[B]FS",
            "[Q]uit",
        };
        drawOverlay(window.?, &overlay_lines, font.?);
        try drawStats(window.?, font.?, pathfinder, allocator);

        sfml.sfRenderWindow_display(window);
    }

    std.debug.print("Maze generator closed!\n", .{});
}
