import 'package:flutter/widgets.dart';

class QuexBreakpoints {
  static const double tablet = 840;
  static const double desktop = 1200;
}

bool isTabletLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= QuexBreakpoints.tablet;
}

bool isDesktopLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= QuexBreakpoints.desktop;
}
