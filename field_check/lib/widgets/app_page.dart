import 'package:flutter/material.dart';
import 'package:field_check/utils/app_theme.dart';

class AppPage extends StatelessWidget {
  final String? appBarTitle;
  final bool showAppBar;
  final bool showBack;
  final bool useScaffold;
  final bool useSafeArea;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? padding;
  final bool scroll;
  final double maxContentWidth;
  final Widget child;

  const AppPage({
    super.key,
    required this.child,
    this.appBarTitle,
    this.showAppBar = true,
    this.showBack = false,
    this.useScaffold = true,
    this.useSafeArea = true,
    this.actions,
    this.padding,
    this.scroll = true,
    this.maxContentWidth = 520,
  });

  @override
  Widget build(BuildContext context) {
    final inner = LayoutBuilder(
      builder: (context, constraints) {
        final centered = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Padding(
              padding:
                  padding ??
                  const EdgeInsets.symmetric(horizontal: AppTheme.lg),
              child: child,
            ),
          ),
        );

        final body = scroll
            ? SingleChildScrollView(child: centered)
            : (constraints.hasBoundedHeight && constraints.hasBoundedWidth
                  ? SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: centered,
                    )
                  : centered);

        return body;
      },
    );

    final content = useSafeArea ? SafeArea(child: inner) : inner;

    if (!useScaffold) {
      return content;
    }

    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              title: appBarTitle != null ? Text(appBarTitle!) : null,
              leading: showBack
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.maybePop(context),
                    )
                  : null,
              actions: actions,
            )
          : null,
      body: content,
    );
  }
}
