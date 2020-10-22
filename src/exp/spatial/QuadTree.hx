package exp.spatial;

import haxe.ds.ReadOnlyArray;

@:allow(exp.spatial)
class QuadTree<Data> {
	public final maxElements:Int;
	public final maxDepth:Int;

	final width:Int;
	final height:Int;
	final nodePool:Pool<QuadNode<Data>>;
	final elementPool:Pool<Element<Data>>;
	var root:QuadNode<Data>;

	public function new(width, height, maxElements, maxDepth) {
		this.width = width;
		this.height = height;
		this.maxElements = maxElements;
		this.maxDepth = maxDepth;
		this.root = new QuadNode(this, 0, 0, 0, width, height);
		this.nodePool = new Pool();
		this.elementPool = new Pool();
	}

	public inline function insert(data, x1, y1, x2, y2) {
		root.insert(getElement(data, Std.int(x1), Std.int(y1), Std.int(x2), Std.int(y2)));
	}

	public inline function clear() {
		root.clear();
		root = getNode(0, 0, 0, width, height);
	}

	public inline function traverse(onNode) {
		root.traverse(onNode);
	}

	public inline function query(x1, y1, x2, y2, ?out) {
		if (out == null)
			out = [];
		return root.query(x1, y1, x2, y2, out);
	}

	function getNode(depth, x1, y1, x2, y2) {
		return nodePool.get(node -> node.reset(depth, x1, y1, x2, y2), () -> new QuadNode(this, depth, x1, y1, x2, y2));
	}

	function getElement(data, x1, y1, x2, y2) {
		return elementPool.get(element -> {
			element.pooled = false;
			element.reset(data, x1, y1, x2, y2);
		}, () -> new Element(data, x1, y1, x2, y2));
	}

	inline function putNode(node) {
		nodePool.put(node);
	}

	inline function putElement(element:Element<Data>) {
		if (!element.pooled) {
			element.pooled = true;
			elementPool.put(element);
		}
	}
}

abstract Pool<T>(Array<T>) {
	public inline function new() {
		this = [];
	}

	public inline function get(reset:T->Void, create:Void->T):T {
		if (this.length > 0) {
			final v = this.pop();
			reset(v);
			return v;
		}
		return create();
	}

	public inline function put(v:T) {
		this.push(v);
	}
}

@:allow(exp.spatial)
class Element<Data> {
	public var data(default, null):Data;
	public var x1(default, null):Int;
	public var y1(default, null):Int;
	public var x2(default, null):Int;
	public var y2(default, null):Int;

	var pooled:Bool = false;

	public function new(data, x1, y1, x2, y2) {
		reset(data, x1, y1, x2, y2);
	}

	public inline function reset(data, x1, y1, x2, y2) {
		this.data = data;
		this.x1 = x1;
		this.y1 = y1;
		this.x2 = x2;
		this.y2 = y2;
	}

	public function toString() {
		return 'Element: $data: $x1,$y1,$x2,$y2';
	}
}

@:allow(exp.spatial)
class QuadNode<Data> {
	public var depth(default, null):Int;
	public var x1(default, null):Int;
	public var y1(default, null):Int;
	public var x2(default, null):Int;
	public var y2(default, null):Int;
	public var isBranch(default, null):Bool;
	public var isLeaf(get, never):Bool;

	public var elements(get, never):ReadOnlyArray<Element<Data>>;

	final tree:QuadTree<Data>;
	final _elements:Array<Element<Data>>;

	// leaves
	var leaf1:QuadNode<Data>;
	var leaf2:QuadNode<Data>;
	var leaf3:QuadNode<Data>;
	var leaf4:QuadNode<Data>;

	public function new(tree, depth, x1, y1, x2, y2) {
		this.tree = tree;
		this.depth = depth;
		this.x1 = x1;
		this.y1 = y1;
		this.x2 = x2;
		this.y2 = y2;

		_elements = [];
	}

	public function insert(e:Element<Data>) {
		if (isBranch) {
			// add to leaves if self is branch
			forEachLeaf(leaf -> {
				if (intersect(e.x1, e.y1, e.x2, e.y2, leaf.x1, leaf.y1, leaf.x2, leaf.y2))
					leaf.insert(e);
			});
		} else {
			// add to self if self is leaf
			// trace(elements.length, e);
			_elements.push(e);

			// split if needed
			if (_elements.length > tree.maxElements && depth < tree.maxDepth) {
				isBranch = true;

				// create leaves
				final hx = (x2 - x1) >> 1;
				final hy = (y2 - y1) >> 1;
				final subDepth = depth + 1;
				// trace('spliting', depth, x1, y1, x2, y2);
				// trace('splits into:');
				// trace(subDepth, x1, y1, x1 + hx, y1 + hy);
				// trace(subDepth, x1, y1 + hy, x1 + hx, y2);
				// trace(subDepth, x1 + hx, y1, x2, y1 + hy);
				// trace(subDepth, x1 + hx, y1 + hy, x2, y2);
				leaf1 = tree.getNode(subDepth, x1, y1, x1 + hx, y1 + hy);
				leaf2 = tree.getNode(subDepth, x1, y1 + hy, x1 + hx, y2);
				leaf3 = tree.getNode(subDepth, x1 + hx, y1, x2, y1 + hy);
				leaf4 = tree.getNode(subDepth, x1 + hx, y1 + hy, x2, y2);

				// move elements to leaves
				for (e in _elements)
					forEachLeaf(leaf -> {
						if (intersect(e.x1, e.y1, e.x2, e.y2, leaf.x1, leaf.y1, leaf.x2, leaf.y2))
							leaf.insert(e);
					});

				// no longer stores elements since self becomes branch
				_elements.resize(0);
			}
		}
	}

	public function clear() {
		if (isBranch)
			forEachLeaf(leaf -> leaf.clear());

		for (element in _elements)
			tree.putElement(element);

		tree.putNode(this);
	}

	public function traverse(onNode:QuadNode<Data>->Void) {
		onNode(this);
		if (isBranch)
			forEachLeaf(leaf -> leaf.traverse(onNode));
	}

	public function query(x1, y1, x2, y2, out:Array<Element<Data>>) {
		if (isBranch) {
			// decent into leaves if self is branch
			forEachLeaf(leaf -> {
				if (intersect(x1, y1, x2, y2, leaf.x1, leaf.y1, leaf.x2, leaf.y2))
					leaf.query(x1, y1, x2, y2, out);
			});
		} else {
			// add elements if self is leaf
			for (e in _elements)
				if (intersect(x1, y1, x2, y2, e.x1, e.y1, e.x2, e.y2))
					out.push(e);
		}
	}

	public inline function reset(depth, x1, y1, x2, y2) {
		this.depth = depth;
		this.x1 = x1;
		this.y1 = y1;
		this.x2 = x2;
		this.y2 = y2;

		isBranch = false;
		leaf1 = leaf2 = leaf3 = leaf4 = null;
		_elements.resize(0);
	}

	public function toString() {
		return 'QuadNode: $depth: $x1,$y1,$x2,$y2';
	}

	inline function get_isLeaf()
		return !isBranch;

	inline function forEachLeaf(f:QuadNode<Data>->Void) {
		f(leaf1);
		f(leaf2);
		f(leaf3);
		f(leaf4);
	}

	inline function get_elements()
		return _elements;

	static inline function intersect(l1:Int, t1:Int, r1:Int, b1:Int, l2:Int, t2:Int, r2:Int, b2:Int) {
		return l2 <= r1 && r2 >= l1 && t2 <= b1 && b2 >= t1;
	}
}
