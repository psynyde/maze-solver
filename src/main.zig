const std = @import("std");
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

    fn draw(self: *Maze, window: *sfml.sfRenderWindow) void {
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
        sfml.sfSprite_setPosition(start_sprite, sfml.sfVector2f{ .x = @as(f32, @floatFromInt(CELL_SIZE)) * 0.15, .y = @as(f32, @floatFromInt(CELL_SIZE)) * 0.15 });
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

    // Create window
    const mode = sfml.sfVideoMode{ .width = WINDOW_WIDTH, .height = WINDOW_HEIGHT, .bitsPerPixel = 32 };
    const window = sfml.sfRenderWindow_create(
        mode,
        "Maze Generator",
        sfml.sfResize | sfml.sfClose,
        null,
    );
    defer sfml.sfRenderWindow_destroy(window);

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
        }

        sfml.sfRenderWindow_clear(window, sfml.sfColor{ .r = 20, .g = 20, .b = 20, .a = 255 });
        maze.draw(window.?);

        const font = sfml.sfFont_createFromFile("assets/font.ttf");
        if (font == null) {
            std.debug.print("Failed to load font\n", .{});
            return error.FontLoadFailed;
        }
        defer sfml.sfFont_destroy(font);

        const overlay_lines = [_][]const u8{
            "[R]egenerate",
            "[Q]uit",
        };
        drawOverlay(window.?, &overlay_lines, font.?);

        sfml.sfRenderWindow_display(window);
    }

    std.debug.print("Maze generator closed!\n", .{});
}
