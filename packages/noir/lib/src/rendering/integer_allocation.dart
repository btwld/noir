/// Allocates every whole cell in [total] proportionally across [weights].
///
/// Tied residues are awarded in document order, keeping terminal layout
/// deterministic when an exact proportional split is impossible.
List<int> allocateExactCells(int total, List<int> weights) {
  if (total < 0) {
    throw ArgumentError.value(total, 'total', 'must be non-negative');
  }
  if (weights.isEmpty) {
    if (total == 0) return const <int>[];
    throw ArgumentError.value(weights, 'weights', 'must not be empty');
  }
  if (weights.any((weight) => weight <= 0)) {
    throw ArgumentError.value(weights, 'weights', 'must all be positive');
  }

  final bigTotal = BigInt.from(total);
  var weightSum = BigInt.zero;
  final bigWeights = <BigInt>[];
  for (final weight in weights) {
    final bigWeight = BigInt.from(weight);
    bigWeights.add(bigWeight);
    weightSum += bigWeight;
  }

  var baseSum = BigInt.zero;
  final quotas = <BigInt>[];
  final ranked = <_Residue>[];
  for (var index = 0; index < bigWeights.length; index++) {
    final numerator = bigTotal * bigWeights[index];
    final base = numerator ~/ weightSum;
    quotas.add(base);
    baseSum += base;
    ranked.add(_Residue(index, numerator % weightSum));
  }
  final left = bigTotal - baseSum;
  if (left.isNegative || left >= BigInt.from(weights.length)) {
    throw StateError('Invalid largest-remainder cell count: $left');
  }
  ranked.sort((a, b) {
    final residueOrder = b.value.compareTo(a.value);
    return residueOrder != 0 ? residueOrder : a.index.compareTo(b.index);
  });
  for (var index = 0; index < left.toInt(); index++) {
    quotas[ranked[index].index] += BigInt.one;
  }

  return quotas
      .map((quota) {
        if (quota.isNegative || quota > bigTotal) {
          throw StateError('Invalid allocated cell quota: $quota');
        }
        return quota.toInt();
      })
      .toList(growable: false);
}

final class _Residue {
  const _Residue(this.index, this.value);

  final int index;
  final BigInt value;
}
