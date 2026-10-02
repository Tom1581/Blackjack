import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Layout checks that look at what the screen actually laid out, not at what
// the code meant: text broken in the middle of a word, text cut off, and
// controls drawn on top of each other. Use them with real fonts loaded
// (support/real_fonts.dart) — the default test font is twice as wide.

/// The phone widths every screen has to survive.
const phoneWidths = [320.0, 360.0, 390.0, 412.0];

/// A plausible height for each width (short 320 phones, tall 412 ones).
double phoneHeight(double width) => switch (width) {
      320 => 568,
      360 => 640,
      390 => 844,
      _ => 915,
    };

bool _isWordChar(int unit) =>
    (unit >= 0x30 && unit <= 0x39) || // 0-9
    (unit >= 0x41 && unit <= 0x5A) || // A-Z
    (unit >= 0x61 && unit <= 0x7A) || // a-z
    unit >= 0xC0; // accented letters and beyond

/// A painter laid out exactly as [p] was — same text, scaling, line limit
/// and width — since RenderParagraph does not expose its line metrics.
TextPainter _painterFor(RenderParagraph p) {
  final painter = TextPainter(
    text: p.text,
    textAlign: p.textAlign,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
    ellipsis: p.overflow == TextOverflow.ellipsis ? '\u2026' : null,
    locale: p.locale,
    strutStyle: p.strutStyle,
    textWidthBasis: p.textWidthBasis,
    textHeightBehavior: p.textHeightBehavior,
  );
  final maxWidth = p.softWrap ? p.constraints.maxWidth : double.infinity;
  painter.layout(maxWidth: maxWidth);
  return painter;
}

Iterable<RenderParagraph> _paragraphs(WidgetTester tester) sync* {
  for (final element in find.byType(RichText).evaluate()) {
    final ro = element.renderObject;
    if (ro is RenderParagraph && ro.hasSize && ro.attached) yield ro;
  }
}

/// Every piece of text whose lines break inside a word, as "text|broken at".
List<String> midWordBreaks(WidgetTester tester) {
  final found = <String>[];
  for (final p in _paragraphs(tester)) {
    final text = p.text.toPlainText();
    if (text.length < 2) continue;
    final painter = _painterFor(p);
    // Text cut short at its line limit is the clipping check's business.
    if (painter.didExceedMaxLines) {
      painter.dispose();
      continue;
    }
    var offset = 0;
    while (offset < text.length) {
      final line = painter.getLineBoundary(TextPosition(offset: offset));
      final end = line.end;
      if (end <= offset) break;
      if (end < text.length &&
          _isWordChar(text.codeUnitAt(end - 1)) &&
          _isWordChar(text.codeUnitAt(end))) {
        found.add('${text.replaceAll('\n', r'\n')}|'
            '${text.substring(0, end).split(RegExp(r'\s')).last}');
      }
      offset = end;
      // Skip the whitespace a soft wrap consumed.
      while (offset < text.length && text[offset] == ' ') {
        offset++;
      }
    }
    painter.dispose();
  }
  return found;
}

/// Text that did not fit: cut off at its line limit, or a single line wider
/// than its box. [allowEllipsis] skips text that is meant to shorten with
/// "…" — player names, for instance.
List<String> clippedTexts(WidgetTester tester, {bool allowEllipsis = true}) {
  final found = <String>[];
  for (final p in _paragraphs(tester)) {
    final text = p.text.toPlainText();
    if (text.trim().isEmpty) continue;
    final ellipsis = p.overflow == TextOverflow.ellipsis;
    if (p.didExceedMaxLines && !(allowEllipsis && ellipsis)) {
      found.add('$text (cut at max lines)');
      continue;
    }
    if (!p.softWrap || p.maxLines == 1) {
      final natural = p.getMaxIntrinsicWidth(double.infinity);
      if (natural > p.size.width + 0.5 && !(allowEllipsis && ellipsis)) {
        found.add('$text (needs ${natural.toStringAsFixed(1)}, '
            'has ${p.size.width.toStringAsFixed(1)})');
      }
    }
  }
  return found;
}

/// Pairs of separate tap targets whose boxes overlap on screen.
///
/// Only what a tap could reach is compared: the part of each control its
/// scroll viewport shows (not what is scrolled under a fixed header), on
/// the topmost route (not the screen beneath an open sheet or dialog).
List<String> overlappingControls(WidgetTester tester) {
  final view = tester.view;
  final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
  bool reachable(Element element, Rect rect) {
    if (!screen.overlaps(rect)) return false;
    return ModalRoute.of(element)?.isCurrent ?? true;
  }

  final targets = <(Element, Rect)>[];
  for (final element in find
      .byWidgetPredicate((w) =>
          (w is InkWell && w.onTap != null) ||
          (w is ButtonStyleButton && w.onPressed != null) ||
          (w is Switch && w.onChanged != null) ||
          (w is GestureDetector && w.onTap != null))
      .evaluate()) {
    final ro = element.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    var rect = ro.localToGlobal(Offset.zero) & ro.size;
    // Only the part its scroll viewport shows can be tapped.
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport is RenderBox) {
      final box = viewport as RenderBox;
      rect = rect.intersect(box.localToGlobal(Offset.zero) & box.size);
    }
    if (rect.width < 1 || rect.height < 1) continue;
    if (!reachable(element, rect)) continue;
    targets.add((element, rect));
  }

  bool nested(Element a, Element b) {
    var found = false;
    a.visitAncestorElements((ancestor) {
      if (ancestor == b) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  // A button is several tap targets inside each other (the button, its
  // InkWell, its GestureDetector); keep only the outermost of each.
  final outer = [
    for (final t in targets)
      if (!targets.any((o) => o.$1 != t.$1 && nested(t.$1, o.$1))) t,
  ];

  final found = <String>[];
  for (var i = 0; i < outer.length; i++) {
    for (var j = i + 1; j < outer.length; j++) {
      final (a, ra) = outer[i];
      final (b, rb) = outer[j];
      final overlap = ra.intersect(rb);
      if (overlap.width <= 1 || overlap.height <= 1) continue;
      if (nested(a, b) || nested(b, a)) continue;
      found.add('${a.widget.runtimeType}$ra ✕ ${b.widget.runtimeType}$rb');
    }
  }
  return found;
}

/// The number of lines [finder]'s text was laid out on.
int lineCount(WidgetTester tester, Finder finder) {
  final p = tester.renderObject<RenderParagraph>(find
      .descendant(of: finder, matching: find.byType(RichText), matchRoot: true)
      .first);
  final painter = _painterFor(p);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

/// All three checks at once, failing with everything found.
void expectCleanLayout(WidgetTester tester, {String where = ''}) {
  final breaks = midWordBreaks(tester);
  final clipped = clippedTexts(tester);
  final overlaps = overlappingControls(tester);
  expect(breaks, isEmpty, reason: '$where: text broken mid-word');
  expect(clipped, isEmpty, reason: '$where: text cut off');
  expect(overlaps, isEmpty, reason: '$where: controls overlap');
}
