import 'dart:math';

import 'package:flutter/material.dart';

/// This traversal policy manage the up and down direction to be totally
/// predictable.
/// Going up or down will always go to the next or previous row. All other
/// traversal policy try to be smart, and in some cases can skip rows when
/// going up or down.
class RowByRowTraversalPolicy extends FocusTraversalPolicy
    with DirectionalFocusTraversalPolicyMixin {
  @override
  Iterable<FocusNode> sortDescendants(
          Iterable<FocusNode> descendants, FocusNode currentNode) =>
      descendants;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    List<FocusNode>? nodes =
        currentNode.nearestScope?.traversalDescendants.toList();
    if (nodes == null) {
      return super.inDirection(currentNode, direction);
    }

    NodeSearcher searcher = NodeSearcher(direction);
    List<CandidateNode> candidates = searcher.findCandidates(nodes, currentNode);
    candidates = _filterToSameVerticalScrollable(candidates, currentNode, direction);
    if (candidates.isEmpty) {
      // Keep horizontal navigation bounded to the current row.
      // Falling back to the default policy here can jump to unrelated widgets
      // (for example WatchNext cards) when pressing right on the last grid item.
      if (direction == TraversalDirection.left ||
          direction == TraversalDirection.right ||
          _isInsideVerticalScrollable(currentNode)) {
        return false;
      }
      return super.inDirection(currentNode, direction);
    }
    FocusNode nextNode = searcher.findBestFocusNode(candidates, currentNode);
    nextNode.requestFocus();
    return true;
  }

  List<CandidateNode> _filterToSameVerticalScrollable(
    List<CandidateNode> candidates,
    FocusNode currentNode,
    TraversalDirection direction,
  ) {
    if (direction != TraversalDirection.up && direction != TraversalDirection.down) {
      return candidates;
    }

    final currentScrollable = _verticalScrollableOf(currentNode);
    if (currentScrollable == null) {
      return candidates;
    }

    return candidates.where((candidate) => _verticalScrollableOf(candidate.node) == currentScrollable).toList();
  }

  bool _isInsideVerticalScrollable(FocusNode node) => _verticalScrollableOf(node) != null;

  ScrollableState? _verticalScrollableOf(FocusNode node) {
    final context = node.context;
    if (context == null) {
      return null;
    }
    return Scrollable.maybeOf(context, axis: Axis.vertical);
  }
}

class NodeSearcher {
  final TraversalDirection directionToSearch;

  NodeSearcher(this.directionToSearch);

  /// should be called first
  List<CandidateNode> findCandidates(
      List<FocusNode> nodes, FocusNode fromNode) {
    final from = CandidateNode(fromNode);
    final List<CandidateNode> candidates = [];

    for (final node in nodes) {
      if (node == fromNode) continue;

      final candidate = CandidateNode(node);
      bool keep = false;
      switch (directionToSearch) {
        case TraversalDirection.up:
          keep = !candidate.isBelowOrEquals(from);
          break;
        case TraversalDirection.down:
          keep = !candidate.isAboveOrEquals(from);
          break;
        case TraversalDirection.right:
          keep = !candidate.isLeftToOrEquals(from) &&
              candidate.isOnTheSameRow(from);
          break;
        case TraversalDirection.left:
          keep = !candidate.isRightToOrEquals(from) &&
              candidate.isOnTheSameRow(from);
          break;
      }
      if (keep) {
        candidates.add(candidate);
      }
    }
    return candidates;
  }

  FocusNode findBestFocusNode(
      List<CandidateNode> candidates, FocusNode fromNode) {
    final from = CandidateNode(fromNode);
    CandidateNode best = candidates.first;

    for (int i = 1; i < candidates.length; i++) {
      final challenger = candidates[i];
      bool useChallenger = false;

      if (directionToSearch == TraversalDirection.down &&
          challenger.isAbove(best)) {
        useChallenger = true;
      } else if (directionToSearch == TraversalDirection.up &&
          challenger.isBelow(best)) {
        useChallenger = true;
      } else if (directionToSearch == TraversalDirection.left &&
          challenger.isRightTo(best)) {
        useChallenger = true;
      } else if (directionToSearch == TraversalDirection.right &&
          challenger.isLeftTo(best)) {
        useChallenger = true;
      } else if (challenger.isOnTheSameRow(best) &&
          challenger.distance(from) < best.distance(from)) {
        useChallenger = true;
      }

      if (useChallenger) {
        best = challenger;
      }
    }

    return best.node;
  }
}

/// An internal object that caches focus node geometry to avoid costly repeated layout queries.
class CandidateNode {
  final FocusNode node;
  final Rect rect;

  CandidateNode(this.node) : rect = node.rect;

  bool isBelow(CandidateNode other) {
    return rect.center.dy.round() > other.rect.center.dy.round();
  }

  bool isBelowOrEquals(CandidateNode other) {
    return rect.center.dy.round() >= other.rect.center.dy.round();
  }

  bool isRightTo(CandidateNode other) {
    return rect.center.dx.round() > other.rect.center.dx.round();
  }

  bool isRightToOrEquals(CandidateNode other) {
    return rect.center.dx.round() >= other.rect.center.dx.round();
  }

  bool isLeftTo(CandidateNode other) {
    return rect.center.dx.round() < other.rect.center.dx.round();
  }

  bool isLeftToOrEquals(CandidateNode other) {
    return rect.center.dx.round() <= other.rect.center.dx.round();
  }

  bool isAbove(CandidateNode other) {
    return rect.center.dy.round() < other.rect.center.dy.round();
  }

  bool isAboveOrEquals(CandidateNode other) {
    return rect.center.dy.round() <= other.rect.center.dy.round();
  }

  bool isOnTheSameRow(CandidateNode other) {
    return rect.center.dy.round() == other.rect.center.dy.round();
  }

  double distance(CandidateNode other) {
    return sqrt(pow(rect.center.dx.round() - other.rect.center.dx.round(), 2) +
        pow(rect.center.dy.round() - other.rect.center.dy.round(), 2));
  }
}
