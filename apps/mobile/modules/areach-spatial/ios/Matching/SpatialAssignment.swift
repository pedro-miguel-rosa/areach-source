import CoreGraphics
import Foundation

enum SpatialAssignment {
    static func assign(
        rowCount: Int,
        columnCount: Int,
        unmatchedCost: Double,
        cost: (Int, Int) -> Double
    ) -> [Int?] {
        guard rowCount > 0 else {
            return []
        }

        let size = max(rowCount, columnCount)
        var matrix = Array(
            repeating: Array(repeating: unmatchedCost, count: size),
            count: size
        )

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let candidateCost = cost(row, column)
                matrix[row][column] = candidateCost.isFinite
                    && candidateCost >= 0
                    && candidateCost < unmatchedCost
                    ? candidateCost
                    : unmatchedCost
            }
        }

        let columns = hungarian(matrix)

        return (0..<rowCount).map { row in
            guard
                let column = columns[row],
                column < columnCount,
                matrix[row][column] < unmatchedCost
            else {
                return nil
            }

            return column
        }
    }

    private static func hungarian(_ matrix: [[Double]]) -> [Int?] {
        let size = matrix.count

        guard size > 0 else {
            return []
        }

        var u = Array(repeating: 0.0, count: size + 1)
        var v = Array(repeating: 0.0, count: size + 1)
        var p = Array(repeating: 0, count: size + 1)
        var way = Array(repeating: 0, count: size + 1)

        for row in 1...size {
            p[0] = row
            var column = 0
            var minValues = Array(repeating: Double.greatestFiniteMagnitude, count: size + 1)
            var used = Array(repeating: false, count: size + 1)

            repeat {
                used[column] = true
                let currentRow = p[column]
                var delta = Double.greatestFiniteMagnitude
                var nextColumn = 0

                for candidateColumn in 1...size where !used[candidateColumn] {
                    let current = matrix[currentRow - 1][candidateColumn - 1]
                        - u[currentRow]
                        - v[candidateColumn]

                    if current < minValues[candidateColumn] {
                        minValues[candidateColumn] = current
                        way[candidateColumn] = column
                    }

                    if minValues[candidateColumn] < delta {
                        delta = minValues[candidateColumn]
                        nextColumn = candidateColumn
                    }
                }

                for candidateColumn in 0...size {
                    if used[candidateColumn] {
                        u[p[candidateColumn]] += delta
                        v[candidateColumn] -= delta
                    } else if candidateColumn > 0 {
                        minValues[candidateColumn] -= delta
                    }
                }

                column = nextColumn
            } while p[column] != 0

            repeat {
                let previousColumn = way[column]
                p[column] = p[previousColumn]
                column = previousColumn
            } while column != 0
        }

        var assignments = Array<Int?>(repeating: nil, count: size)

        for column in 1...size where p[column] != 0 {
            assignments[p[column] - 1] = column - 1
        }

        return assignments
    }
}

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
}

func distance(from point: CGPoint, to rect: CGRect) -> Double {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)

    return hypot(dx, dy)
}
