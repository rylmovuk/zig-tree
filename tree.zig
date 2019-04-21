const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const assert = std.debug.assert;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

/// Generic k-ary tree represented as a "left-child right-sibling" binary tree.
pub fn Tree(comptime T: type) type {
    return struct {
        const Self = @This();
        root: Node,

        /// Node inside the tree.
        pub const Node = struct {
            value: T,
            parent: ?*Node,
            leftmost_child: ?*Node,
            right_sibling: ?*Node,

            fn init(value: T) Node {
                return Node{
                    .value = value,
                    .parent = null,
                    .leftmost_child = null,
                    .right_sibling = null,
                };
            }
        };

        /// Initialize a tree.
        ///
        /// Arguments:
        ///     value: Value (aka weight, key, etc.) of the root node.
        ///
        /// Returns:
        ///     A tree containing one node with specified value.
        pub fn init(value: T) Self {
            return Self{
                .root = Node.init(value),
            };
        }

        /// Allocate a new node. Caller owns returned Node and must free with `destroyNode`.
        ///
        /// Arguments:
        ///     allocator: Dynamic memory allocator.
        ///
        /// Returns:
        ///     A pointer to the new node.
        ///
        /// Errors:
        ///     If a new node cannot be allocated.
        pub fn allocateNode(tree: *Self, allocator: *Allocator) !*Node {
            return allocator.create(Node);
        }

        /// Deallocate a node. Node must have been allocated with `allocator`.
        ///
        /// Arguments:
        ///     node: Pointer to the node to deallocate.
        ///     allocator: Dynamic memory allocator.
        pub fn destroyNode(tree: *Self, node: *Node, allocator: *Allocator) void {
            assert(tree.containsNode(node));
            allocator.destroy(node);
        }

        /// Allocate and initialize a node and its value.
        ///
        /// Arguments:
        ///     value: Value (aka weight, key, etc.) of newly created node.
        ///     allocator: Dynamic memory allocator.
        ///
        /// Returns:
        ///     A pointer to the new node.
        ///
        /// Errors:
        ///     If a new node cannot be allocated.
        pub fn createNode(tree: *Self, value: T, allocator: *Allocator) !*Node {
            var node = try tree.allocateNode(allocator);
            node.* = Node.init(value);
            return node;
        }

        /// Insert a node at the specified position inside the tree.
        ///
        /// Arguments:
        ///     node: Pointer to the node to insert.
        ///     parent: Pointer to node which the newly created node will be a child of.
        ///
        /// Returns:
        ///     A pointer to the new node.
        pub fn insert(tree: *Self, node: *Node, parent: *Node) void {
            node.parent = parent;
            node.right_sibling = parent.leftmost_child;
            parent.leftmost_child = node;
        }

        /// Add another tree at the specified position inside this tree.
        ///
        /// Arguments:
        ///     other: Pointer to the tree to insert.
        ///     parent: Pointer to node which the newly created node will be a parent of.
        pub fn graft(tree: *Self, other: *Self, parent: *Node) void {}

        /// Remove (detach) a "branch" from the tree (remove node and all its descendants).
        /// Does nothing when applied to root node.
        ///
        /// Arguments:
        ///     node: Pointer to node to be removed.
        pub fn prune(tree: *Self, node: *Node) void {
            assert(tree.containsNode(node));
            if (node.parent) |parent| {
                var ptr = &parent.leftmost_child;
                while (ptr.*) |sibling| : (ptr = &sibling.right_sibling) {
                    if (sibling == node) {
                        ptr.* = node.right_sibling;
                        break;
                    }
                }
                node.right_sibling = null;
                node.parent = null;
            }
        }

        /// Remove a node preserving all its children, which take its place inside the tree.
        /// Does nothing when applied to root node.
        ///
        /// Arguments:
        ///     node: Pointer to node to be removed.
        pub fn remove(tree: *Self, node: *Node) void {
            assert(tree.containsNode(node));
            if (node.parent) |parent| {
                var ptr = &parent.leftmost_child;
                while (ptr.*) |sibling| : (ptr = &sibling.right_sibling) {
                    if (sibling == node) break;
                }
                ptr.* = node.leftmost_child;
                while (ptr.*) |old_child| : (ptr = &old_child.right_sibling) {
                    old_child.parent = parent;
                }
                ptr.* = node.right_sibling;
                node.parent = null;
                node.leftmost_child = null;
                node.right_sibling = null;
            }
        }

        /// Iterator that performs a depth-first post-order traversal of the tree.
        /// It is non-recursive and uses constant memory (no allocator needed).
        pub const DepthFirstIterator = struct {
            const State = enum {
                GoDeeper,
                GoBroader,
            };
            tree: *Self,
            current: ?*Node,
            state: State,

            // NB:
            // If not children_done:
            //      Go as deep as possible
            // Yield node
            // If can move right:
            //      children_done = false;
            //      Move right
            // Else:
            //      children_done = true;
            //      Move up

            pub fn init(tree: *Self) DepthFirstIterator {
                return DepthFirstIterator{
                    .tree = tree,
                    .current = &tree.root,
                    .state = State.GoDeeper,
                };
            }

            pub fn next(it: *DepthFirstIterator) ?*Node {
                // State machine
                while (it.current) |current| {
                    switch (it.state) {
                        State.GoDeeper => {
                            // Follow child node until deepest possible level
                            if (current.leftmost_child) |child| {
                                it.current = child;
                            } else {
                                it.state = State.GoBroader;
                                return current;
                            }
                        },
                        State.GoBroader => {
                            if (current.right_sibling) |sibling| {
                                it.current = sibling;
                                it.state = State.GoDeeper;
                            } else {
                                it.current = current.parent;
                                return current.parent;
                            }
                        },
                    }
                }
                return null;
            }

            pub fn reset(it: *DepthFirstIterator) void {
                it.current = it.tree.root;
            }
        };

        /// Get a depth-first iterator over the nodes of this tree.
        ///
        /// Returns:
        ///     An iterator struct (one containing `next` and `reset` member functions).
        pub fn depthFirstIterator(tree: *Self) DepthFirstIterator {
            return DepthFirstIterator.init(tree);
        }

        /// Check if a node is contained in this tree.
        ///
        /// Arguments:
        ///     target: Pointer to node to be searched for.
        ///
        /// Returns:
        ///     A bool telling whether it has been found.
        pub fn containsNode(tree: *Self, target: *Node) bool {
            var iter = tree.depthFirstIterator();
            while (iter.next()) |node| {
                if (node == target) {
                    return true;
                }
            }
            return false;
        }
    };
}

test "tree node insertion" {
    var tree = Tree(u32).init(1);

    const allocator = std.debug.global_allocator;
    //var buffer: [5000]u8 = undefined;
    // const allocator = &FixedBufferAllocator.init(buffer[0..]).allocator;

    var two = try tree.createNode(2, allocator);
    var three = try tree.createNode(3, allocator);
    var four = try tree.createNode(4, allocator);
    var five = try tree.createNode(5, allocator);
    var six = try tree.createNode(6, allocator);
    var fortytwo = try tree.createNode(42, allocator);
    defer {
        tree.destroyNode(two, allocator);
        tree.destroyNode(three, allocator);
        tree.destroyNode(four, allocator);
        tree.destroyNode(five, allocator);
        tree.destroyNode(six, allocator);
        allocator.destroy(fortytwo);
    }

    tree.insert(two, &tree.root);
    tree.insert(three, &tree.root);
    tree.insert(four, &tree.root);
    tree.insert(five, two);
    tree.insert(six, two);

    testing.expect(tree.root.value == 1);
    testing.expect(two.parent == &tree.root);
    testing.expect(three.parent == &tree.root);
    testing.expect(tree.containsNode(four));
    testing.expect(five.parent == two);
    testing.expect(!tree.containsNode(fortytwo));

    var iter = tree.depthFirstIterator();
    while (iter.next()) |node| {
        std.debug.warn("{} ", node.value);
    }
}

test "tree node removal" {
    var tree = Tree(u32).init(1);

    const allocator = std.debug.global_allocator;

    var two = try tree.createNode(2, allocator);
    var three = try tree.createNode(3, allocator);
    var four = try tree.createNode(4, allocator);
    var five = try tree.createNode(5, allocator);
    var six = try tree.createNode(6, allocator);
    defer {
        tree.destroyNode(three, allocator);
        tree.destroyNode(four, allocator);
        allocator.destroy(two);
        allocator.destroy(five);
        allocator.destroy(six);
    }

    tree.insert(two, &tree.root);
    tree.insert(three, &tree.root);
    tree.insert(four, &tree.root);
    tree.insert(five, two);
    tree.insert(six, two);

    tree.prune(two);

    testing.expect(tree.containsNode(three));
    testing.expect(tree.containsNode(four));
    testing.expect(!tree.containsNode(two));
    testing.expect(!tree.containsNode(five));
    testing.expect(!tree.containsNode(six));
    var iter = tree.depthFirstIterator();
    while (iter.next()) |node| {
        std.debug.warn("{} ", node.value);
    }
}
