import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// Inline-safe latex builder.
///
/// The default [LatexElementBuilder] returns [SingleChildScrollView] which
/// is opaque to [_getInlineSpanFromText], breaking the text-merge chain and
/// causing each text segment around a math expression to become a full-width
/// [RichText] — resulting in unwanted newlines around inline math.
///
/// By returning [Text.rich] with a [WidgetSpan], the builder produces a widget
/// that [_getInlineSpanFromText] recognises, so the span merges with adjacent
/// text into a single [RichText] and math flows correctly inline.
class _InlineLatexBuilder extends MarkdownElementBuilder {
  _InlineLatexBuilder({this.textStyle});

  final TextStyle? textStyle;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent;
    if (text.isEmpty) return const SizedBox.shrink();

    final isDisplay = element.attributes['MathStyle'] == 'display';
    final mathStyle = isDisplay ? MathStyle.display : MathStyle.text;
    final style = textStyle ?? preferredStyle ?? parentStyle;

    if (isDisplay) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.antiAlias,
        child: Math.tex(text, textStyle: style, mathStyle: mathStyle),
      );
    }

    // Inline math: wrap in Text.rich so _mergeInlineChildren can merge spans.
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(text, textStyle: style, mathStyle: mathStyle),
          ),
        ],
      ),
    );
  }
}

/// Drop-in [MarkdownBody] wrapper with inline-safe math rendering.
class MathMarkdownBody extends StatelessWidget {
  const MathMarkdownBody({
    super.key,
    required this.data,
    this.styleSheet,
    this.textStyle,
  });

  final String data;
  final MarkdownStyleSheet? styleSheet;

  /// Style applied to math expressions. Should match the surrounding text.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      styleSheet: styleSheet,
      builders: {
        'latex': _InlineLatexBuilder(textStyle: textStyle),
      },
      extensionSet: md.ExtensionSet(
        [LatexBlockSyntax()],
        [LatexInlineSyntax()],
      ),
    );
  }
}
