import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../localization/app_language.dart';

class LText extends StatelessWidget {
  const LText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: AppLanguageController.language,
    builder: (_, __, ___) => Text(
      tr(data),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    ),
  );
}

class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    onTapDown: (_) => setState(() => down = true),
    onTapCancel: () => setState(() => down = false),
    onTapUp: (_) => setState(() => down = false),
    child: AnimatedScale(
      scale: down ? .97 : 1,
      duration: const Duration(milliseconds: 120),
      child: widget.child,
    ),
  );
}

class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0C10233F),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
    child: Row(
      children: [
        Expanded(
          child: LText(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            child: LText(
              action!,
              style: const TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    ),
  );
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.initials,
    this.color = AppColors.sky,
    this.size = 46,
  });
  final String initials;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(colors: [color.withValues(alpha: .55), color]),
    ),
    child: LText(
      initials,
      style: TextStyle(
        fontWeight: FontWeight.w900,
        color: Colors.white,
        fontSize: size * .3,
      ),
    ),
  );
}

class AppButton extends StatelessWidget {
  const AppButton(this.label, {super.key, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 58,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon),
      label: LText(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
  );
}

class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    duration: Duration(milliseconds: 500 + delay.inMilliseconds),
    tween: Tween(begin: 0, end: 1),
    curve: Curves.easeOutCubic,
    builder: (_, v, c) => Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c),
    ),
    child: child,
  );
}
