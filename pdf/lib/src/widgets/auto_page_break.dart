/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../../pdf.dart';
import '../../widgets.dart';

/// Context for tracking the state of an auto-breaking widget across pages.
class AutoPageBreakContext extends WidgetContext {
  /// The vertical offset where the next chunk should start (from top)
  double consumedHeight = 0;

  /// Whether all content has been rendered
  bool isComplete = false;

  @override
  void apply(AutoPageBreakContext other) {
    consumedHeight = other.consumedHeight;
    isComplete = other.isComplete;
  }

  @override
  WidgetContext clone() {
    return AutoPageBreakContext()..apply(this);
  }

  @override
  String toString() =>
      '$runtimeType consumedHeight: $consumedHeight isComplete: $isComplete';

  @override
  bool isEqualTo(AutoPageBreakContext other) =>
      consumedHeight == other.consumedHeight && isComplete == other.isComplete;
}

/// A widget that automatically breaks its child widget across multiple pages
/// when the child exceeds the available page height.
///
/// This widget is useful for wrapping arbitrary widgets that don't natively
/// support page spanning, such as large containers, images, or custom widgets.
///
/// The breaking algorithm works by:
/// 1. Laying out the child widget with unconstrained height
/// 2. Determining how much of the child fits on the current page
/// 3. Clipping and painting only the visible portion
/// 4. Continuing on the next page from where it left off
///
/// Example:
/// ```dart
/// MultiPage(
///   build: (context) => [
///     AutoPageBreak(
///       child: Container(
///         height: 2000, // A very tall container
///         color: PdfColors.blue,
///         child: Center(child: Text('This will break across pages')),
///       ),
///     ),
///   ],
/// )
/// ```
class AutoPageBreak extends Widget with SpanningWidget {
  /// Creates an auto page break widget.
  ///
  /// The [child] is the widget that will be automatically broken across pages
  /// if it exceeds the available height.
  ///
  /// If [allowOrphanedContent] is false (default), the widget will avoid
  /// leaving very small portions of content on a page.
  ///
  /// [minChunkHeight] specifies the minimum height of content that should
  /// be rendered on a single page before breaking. Default is 20 points.
  AutoPageBreak({
    required this.child,
    this.allowOrphanedContent = false,
    this.minChunkHeight = 20,
  });

  /// The child widget to be rendered, potentially spanning multiple pages.
  final Widget child;

  /// Whether to allow very small pieces of content at page breaks.
  final bool allowOrphanedContent;

  /// Minimum height of content to render on a page.
  final double minChunkHeight;

  /// Internal context tracking rendering state
  final AutoPageBreakContext _context = AutoPageBreakContext();

  /// Cached full height of the child
  double? _fullChildHeight;

  /// Height consumed in the current layout call (for paint reference)
  double _currentChunkHeight = 0;

  /// Starting offset for the current chunk
  double _currentStartOffset = 0;

  @override
  bool get canSpan => true;

  @override
  bool get hasMoreWidgets => !_context.isComplete;

  @override
  WidgetContext saveContext() => _context;

  @override
  void restoreContext(AutoPageBreakContext context) {
    _context.apply(context);
  }

  @override
  void layout(Context context, BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    // First, layout the child with unconstrained height to get its full size
    // Only do this once per widget
    if (_fullChildHeight == null) {
      child.layout(
        context,
        BoxConstraints(
          minWidth: constraints.minWidth,
          maxWidth: constraints.maxWidth,
          // Remove height constraints to get full child height
        ),
        parentUsesSize: true,
      );
      _fullChildHeight = child.box!.height;
    }

    final availableHeight = constraints.maxHeight;
    final remainingHeight = _fullChildHeight! - _context.consumedHeight;

    // Store the starting offset for this chunk (for paint method)
    _currentStartOffset = _context.consumedHeight;

    // Check if this is the first render and child fits in available space
    if (_context.consumedHeight == 0 && _fullChildHeight! <= availableHeight) {
      // Child fits entirely, no need for breaking
      box = PdfRect(0, 0, child.box!.width, _fullChildHeight!);
      _currentChunkHeight = _fullChildHeight!;
      _context.consumedHeight = _fullChildHeight!;
      _context.isComplete = true;
      return;
    }

    // Calculate how much content we can show on this page
    double chunkHeight;
    if (remainingHeight <= availableHeight) {
      // All remaining content fits on this page
      chunkHeight = remainingHeight;
      _context.consumedHeight = _fullChildHeight!;
      _context.isComplete = true;
    } else {
      // Need to break - show as much as fits
      chunkHeight = availableHeight;

      // Avoid orphaned content (tiny pieces at page break)
      if (!allowOrphanedContent && chunkHeight < minChunkHeight) {
        // Skip this page and try on the next one
        chunkHeight = 0;
      } else {
        // Update the consumed height for subsequent calls
        _context.consumedHeight += chunkHeight;
      }
    }

    _currentChunkHeight = chunkHeight;

    // Create the bounding box for this chunk
    box = PdfRect(0, 0, child.box!.width, math.max(0, chunkHeight));
  }

  @override
  void paint(Context context) {
    super.paint(context);

    if (box == null || box!.height <= 0 || _currentChunkHeight <= 0) {
      return;
    }

    // We need to clip to only show the portion of the child for this page
    // The child's coordinate system has origin at bottom-left,
    // so we need to calculate the correct offset

    context.canvas.saveContext();

    // Set up clipping rectangle to show only the current chunk
    context.canvas.drawRect(
      box!.left,
      box!.bottom,
      box!.width,
      box!.height,
    );
    context.canvas.clipPath();

    // Transform to position the child correctly
    // We need to offset the child so that the correct portion is visible
    // The offset from the top of the child that we've consumed before this chunk
    final yOffset =
        _fullChildHeight! - _currentStartOffset - _currentChunkHeight;

    final mat = Matrix4.identity();
    mat.translateByDouble(box!.left, box!.bottom - yOffset, 0, 1);
    context.canvas.setTransform(mat);

    // Paint the child
    child.paint(context);

    context.canvas.restoreContext();
  }

  @override
  void debugPaint(Context context) {
    context.canvas
      ..setStrokeColor(PdfColors.red)
      ..setLineWidth(2)
      ..drawBox(box!)
      ..strokePath();
  }
}

/// A helper widget that breaks a column of widgets across pages.
/// Unlike a regular [Column] which may overflow, this widget ensures
/// each child is properly handled and large children are automatically broken.
///
/// This is useful when you have a mix of fixed-size and variable-size widgets
/// and want them all to break properly across pages.
class BreakableColumn extends Widget with SpanningWidget {
  /// Creates a breakable column.
  ///
  /// [children] are the widgets to display in a column.
  /// [spacing] is the vertical spacing between children.
  /// [wrapOversized] if true, automatically wraps oversized children
  /// in [AutoPageBreak] widgets.
  BreakableColumn({
    required this.children,
    this.spacing = 0,
    this.wrapOversized = true,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final List<Widget> children;
  final double spacing;
  final bool wrapOversized;
  final CrossAxisAlignment crossAxisAlignment;

  final BreakableColumnContext _context = BreakableColumnContext();

  @override
  bool get canSpan => true;

  @override
  bool get hasMoreWidgets => _context.currentChildIndex < children.length;

  @override
  WidgetContext saveContext() => _context;

  @override
  void restoreContext(BreakableColumnContext context) {
    _context.apply(context);
  }

  @override
  void layout(Context context, BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    final maxWidth = constraints.maxWidth;
    final maxHeight = constraints.maxHeight;

    var currentY = 0.0;
    var maxChildWidth = 0.0;

    _context.childrenOnThisPage.clear();

    for (var i = _context.currentChildIndex; i < children.length; i++) {
      var child = children[i];

      // Use the wrapped child if continuing
      if (i == _context.currentChildIndex &&
          _context.currentWrappedChild != null) {
        child = _context.currentWrappedChild!;
      }

      // Add spacing between children
      if (_context.childrenOnThisPage.isNotEmpty) {
        currentY += spacing;
      }

      // Layout the child
      child.layout(
        context,
        BoxConstraints(maxWidth: maxWidth),
        parentUsesSize: true,
      );

      final childHeight = child.box!.height;
      final childWidth = child.box!.width;

      // Check if child fits on this page
      if (currentY + childHeight > maxHeight) {
        // Child doesn't fit entirely
        if (currentY == 0 && childHeight > maxHeight) {
          // Child is larger than the page and we're at the top
          if (wrapOversized) {
            // Wrap in AutoPageBreak if not already wrapped
            if (child is! AutoPageBreak) {
              child = AutoPageBreak(child: child);
            }
            child.layout(
              context,
              BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
              parentUsesSize: true,
            );

            // Position and add the wrapped child
            final x = _calculateChildX(childWidth, maxWidth);
            child.box = PdfRect(x, 0, child.box!.width, child.box!.height);
            _context.childrenOnThisPage.add(child);
            currentY += child.box!.height;

            // Check if the auto-break child has more content
            if (child.hasMoreWidgets) {
              _context.currentWrappedChild = child;
              _context.childContext = (child as SpanningWidget).saveContext();
              break;
            }
            _context.currentWrappedChild = null;
          } else {
            // Skip to next child - this will cause the original error
            continue;
          }
        } else {
          // We have some content, break here
          break;
        }
      } else {
        // Child fits, add it
        final x = _calculateChildX(childWidth, maxWidth);
        child.box = PdfRect(x, 0, childWidth, childHeight);
        _context.childrenOnThisPage.add(child);
        currentY += childHeight;
        _context.currentWrappedChild = null;
      }

      _context.currentChildIndex = i + 1;
    }

    // Position children from top to bottom
    var y = currentY;
    for (final child in _context.childrenOnThisPage) {
      y -= child.box!.height;
      child.box = PdfRect(
        child.box!.left,
        y,
        child.box!.width,
        child.box!.height,
      );
      y -= spacing;
    }

    maxChildWidth = _context.childrenOnThisPage
        .fold(0.0, (max, child) => math.max(max, child.box!.width));

    box = PdfRect(0, 0, maxChildWidth, currentY);
  }

  double _calculateChildX(double childWidth, double maxWidth) {
    switch (crossAxisAlignment) {
      case CrossAxisAlignment.start:
        return 0;
      case CrossAxisAlignment.end:
        return maxWidth - childWidth;
      case CrossAxisAlignment.center:
        return (maxWidth - childWidth) / 2;
      case CrossAxisAlignment.stretch:
        return 0;
    }
  }

  @override
  void paint(Context context) {
    super.paint(context);

    final mat = Matrix4.identity();
    mat.translateByDouble(box!.left, box!.bottom, 0, 1);
    context.canvas
      ..saveContext()
      ..setTransform(mat);

    for (final child in _context.childrenOnThisPage) {
      child.paint(context);
    }

    context.canvas.restoreContext();
  }
}

/// Context for tracking the state of a BreakableColumn widget across pages.
class BreakableColumnContext extends WidgetContext {
  /// The index of the first child to render on the current page.
  int currentChildIndex = 0;

  /// The wrapped child that's currently being rendered across pages.
  Widget? currentWrappedChild;

  /// The context of the wrapped child
  WidgetContext? childContext;

  /// Children that have been laid out on the current page.
  List<Widget> childrenOnThisPage = <Widget>[];

  @override
  void apply(BreakableColumnContext other) {
    currentChildIndex = other.currentChildIndex;
    currentWrappedChild = other.currentWrappedChild;
    childContext = other.childContext;
  }

  @override
  WidgetContext clone() {
    return BreakableColumnContext()..apply(this);
  }

  @override
  bool isEqualTo(BreakableColumnContext other) {
    if (currentChildIndex != other.currentChildIndex) {
      return false;
    }
    if (currentWrappedChild != other.currentWrappedChild) {
      return false;
    }

    if (childContext == null && other.childContext == null) {
      return true;
    }
    if (childContext == null || other.childContext == null) {
      return false;
    }
    return childContext!.isEqualTo(other.childContext!);
  }
}
