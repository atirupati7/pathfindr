// AStar.swift
import Foundation

struct AStar {
    struct Node: Hashable { let x:Int; let z:Int }

    static func path(from start: SIMD2<Int>, to goal: SIMD2<Int>, in grid: OccupancyGrid) -> [SIMD2<Int>]? {
        let startN = Node(x: start.x, z: start.y)
        let goalN = Node(x: goal.x, z: goal.y)
        var open: Set<Node> = [startN]
        var came: [Node: Node] = [:]
        var g: [Node: Float] = [startN: 0]
        var f: [Node: Float] = [startN: h(startN, goalN)]
        var heap: [(Float, Node)] = [(f[startN]!, startN)]

        func popMin() -> Node? {
            guard !heap.isEmpty else { return nil }
            heap.sort { $0.0 < $1.0 }
            return heap.removeFirst().1
        }
        func push(_ n: Node, _ pr: Float) { heap.append((pr,n)) }

        while !open.isEmpty {
            guard let current = popMin() else { break }
            if current == goalN { return reconstruct(current, came).map { SIMD2<Int>($0.x, $0.z) } }
            open.remove(current)
            for (nx, nz, cost) in neighbors(of: current, grid: grid) {
                let n = Node(x: nx, z: nz)
                let tentativeG = (g[current] ?? .infinity) + cost
                if tentativeG < (g[n] ?? .infinity) {
                    came[n] = current
                    g[n] = tentativeG
                    let nf = tentativeG + h(n, goalN)
                    f[n] = nf
                    if !open.contains(n) { open.insert(n); push(n, nf) }
                }
            }
        }
        return nil
    }

    private static func h(_ a: Node, _ b: Node) -> Float {
        let dx = Float(a.x - b.x)
        let dz = Float(a.z - b.z)
        return hypotf(dx, dz)
    }

    private static func reconstruct(_ end: Node, _ came: [Node: Node]) -> [Node] {
        var path: [Node] = [end]
        var cur = end
        while let prev = came[cur] { path.append(prev); cur = prev }
        return path.reversed()
    }

    private static func neighbors(of n: Node, grid: OccupancyGrid) -> [(Int,Int,Float)] {
        let dirs = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]
        var res: [(Int,Int,Float)] = []
        for (dx,dz) in dirs {
            let x = n.x+dx, z=n.z+dz
            if !grid.isOccupied(x: x, z: z) {
                let cost: Float = (dx==0 || dz==0) ? 1.0 : 1.4142
                res.append((x,z,cost))
            }
        }
        return res
    }
}
