import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/constants.dart';
import '../../../app/routes.dart';

/// Cold-start splash / welcome animation — v3, "bright premium" edition.
///
/// A fixed 6-second cinematic sequence, entirely from Flutter
/// primitives (gradients, blur, shadows, custom painting) — no photo
/// or external art asset is used anywhere in this screen:
///
///   0.00s – 1.50s  washing machine fades/scales into view (no bounce)
///   0.30s – 2.10s  faint delivery-map backdrop fades in behind it
///   0.00s – 6.00s  drum spins, clothes tumble, suds shift, machine
///                  floats gently up/down, cyan light sweeps across it
///   0.00s – 6.00s  bubbles rise and background particles twinkle
///   1.80s – 3.00s  logo badge fades/scales in
///   2.52s – 3.96s  title slides/fades up into place, then keeps a
///                  continuous, subtle vertical "jump" loop
///   3.00s – 4.44s  tagline slides/fades up (slightly after the
///                  title), then keeps its own out-of-phase jump loop
///   4.80s – 6.00s  bubble outro: a second, denser population of
///                  bubbles rises from the bottom/sides with
///                  progressively increasing frequency and size,
///                  gradually engulfing the whole screen (machine,
///                  logo, title, tagline, background) in a soft
///                  bubble curtain, with a final gentle wash in the
///                  last ~0.2–0.3s to smooth the hand-off
///   6.00s          hands off to [AppRoutes.gate] (existing [AuthGate])
///
/// Nothing about session/role resolution changes here — this screen
/// only owns the first impression.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Total runtime of the splash, per spec: exactly 6 seconds before
  /// we navigate away — not a shorter animation plus an extra delay.
  static const _totalDuration = Duration(milliseconds: 6000);

  /// One-shot entrance choreography (machine, map, logo, title, tagline).
  late final AnimationController _controller;

  /// Continuous loop for everything that should keep animating for the
  /// full 6 seconds regardless of entrance timing: drum spin, floating
  /// bob, bubbles, particles, the cyan light sweep, and the title /
  /// tagline "jump" cycles. Chosen so every periodic motion below
  /// completes a whole number of cycles per loop, which keeps the
  /// `repeat()` wrap seamless.
  late final AnimationController _loopController;

  late final List<_BubbleSpec> _bubbles;
  late final List<_ParticleSpec> _particles;
  late final List<_BuildingSpec> _buildings;

  /// The dense, one-shot outro population — entirely separate from
  /// [_bubbles] (which are the small ambient bubbles that rise for
  /// the whole 6s). These are keyed to [_controller]'s 0..1 timeline
  /// directly (not the repeating [_loopController]), since each one
  /// plays exactly once, near the very end, and must never restart.
  late final List<_OutroBubbleSpec> _outroBubbles;

  // Phase windows, expressed as fractions of [_controller]'s duration
  // (a fraction of 6000ms). Deliberately gentle, non-overshooting
  // curves throughout — the brief for this pass calls for realism and
  // restraint over a bouncy "demo" feel.
  static const _machineIn = Interval(0.00, 0.25, curve: Curves.easeOutCubic);
  static const _mapIn = Interval(0.05, 0.35, curve: Curves.easeOut);
  static const _logoIn = Interval(0.30, 0.50, curve: Curves.easeOutCubic);
  static const _titleIn = Interval(0.42, 0.66, curve: Curves.easeOut);
  static const _taglineIn = Interval(0.50, 0.74, curve: Curves.easeOut);

  /// Outro window, as a fraction of the 6s total: 0.80 → 4.80s,
  /// 1.00 → 6.00s. Everything in the "Animation sequence" spec
  /// (bubbles starting to appear more often ~4.8s, rising from
  /// 5.2s, a surge at 5.5s, full coverage by 5.8–6.0s) is derived
  /// from where each bubble's own `spawnT` falls inside this window.
  static const _outroStart = 0.80;
  static const _outroSpan = 0.20;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _totalDuration,
    )..forward();

    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _goNext();
      }
    });

    final random = math.Random(7); // fixed seed: same layout every run
    _bubbles = List.generate(12, (i) {
      return _BubbleSpec(
        dx: -0.6 + random.nextDouble() * 1.2,
        size: 4 + random.nextDouble() * 12,
        speed: 0.5 + random.nextDouble() * 1.0,
        phase: random.nextDouble(),
        blur: random.nextDouble() * 1.6,
        wobble: 0.02 + random.nextDouble() * 0.04,
      );
    });

    _particles = List.generate(18, (i) {
      return _ParticleSpec(
        dx: random.nextDouble(),
        dy: random.nextDouble(),
        size: 0.8 + random.nextDouble() * 1.8,
        speed: 0.10 + random.nextDouble() * 0.22,
        phase: random.nextDouble(),
      );
    });

    _buildings = List.generate(14, (i) {
      return _BuildingSpec(
        dx: random.nextDouble(),
        dy: random.nextDouble() * 0.7,
        width: 14 + random.nextDouble() * 30,
        height: 14 + random.nextDouble() * 30,
      );
    });

    // Separate, fixed-seed random for the outro so tuning bubble
    // counts/sizes above never shifts which frame the ambient
    // bubbles/particles/buildings land on, or vice versa.
    final outroRandom = math.Random(42);
    _outroBubbles = List.generate(90, (i) {
      // sqrt() skews spawn times toward the *end* of the outro
      // window: most bubbles are still unspawned early on (sparse,
      // ~4.8s), and the remaining spawn budget clusters tighter and
      // tighter as t → 1.0, which is what reads as "bubbles begin
      // appearing more frequently" → "significantly more bubbles" →
      // "cover most/all of the screen" rather than a flat drizzle.
      final spawnT = (_outroStart + math.sqrt(outroRandom.nextDouble()) * _outroSpan)
          .clamp(0.0, _outroStart + _outroSpan - 0.01);

      // 0 = small/background/blurred, 1 = large/foreground/sharp —
      // the "largest bubbles appear closer to the viewer" parallax
      // cue from the brief.
      final depth = outroRandom.nextDouble();

      final edgeRoll = outroRandom.nextDouble();
      final edge = edgeRoll < 0.55
          ? _BubbleEdge.bottom
          : (edgeRoll < 0.78 ? _BubbleEdge.left : _BubbleEdge.right);

      final variantRoll = outroRandom.nextDouble();
      final variant = variantRoll < 0.35
          ? _BubbleColorVariant.transparent
          : variantRoll < 0.60
              ? _BubbleColorVariant.white
              : variantRoll < 0.85
                  ? _BubbleColorVariant.cyanLight
                  : _BubbleColorVariant.tealGlow;

      return _OutroBubbleSpec(
        spawnT: spawnT,
        // How much of the *remaining* controller timeline this one
        // bubble takes to rise in and settle — short enough that even
        // a bubble spawned late still finishes comfortably before
        // t = 1.0, long enough that none of them snap into place.
        durationFraction: 0.10 + outroRandom.nextDouble() * 0.16,
        edge: edge,
        targetDx: outroRandom.nextDouble(),
        targetDy: outroRandom.nextDouble(),
        // Small/medium/large/large-foreground mix, biased by depth so
        // foreground bubbles read distinctly bigger, not just a
        // uniform random scatter of sizes.
        baseSize: 10 + depth * 130 + outroRandom.nextDouble() * 18,
        depth: depth,
        wobbleAmp: 0.015 + outroRandom.nextDouble() * 0.045,
        wobbleFreq: 1.4 + outroRandom.nextDouble() * 2.2,
        wobblePhase: outroRandom.nextDouble() * math.pi * 2,
        variant: variant,
      );
    });
  }

  void _goNext() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.gate);
  }

  @override
  void dispose() {
    _controller.dispose();
    _loopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final shortestSide = math.min(size.width, size.height);
    // Responsive hero height: generous on tall phones, capped so the
    // machine never crowds the text on short/wide screens or tablets.
    final heroHeight = (size.height * 0.40).clamp(260.0, 380.0).toDouble();
    // Scale factor so the machine and type shrink gracefully on small
    // devices instead of clipping.
    final uiScale = (shortestSide / 390.0).clamp(0.82, 1.15).toDouble();

    return Scaffold(
      backgroundColor: _Palette.bgWhite,
      body: AnimatedBuilder(
        animation: Listenable.merge([_controller, _loopController]),
        builder: (context, _) {
          final t = _controller.value;
          final loopT = _loopController.value;
          // 0..1 breathing value for the cyan glow / light sweep —
          // one full breath per loop.
          final pulse = 0.5 + 0.5 * math.sin(loopT * 2 * math.pi);
          // Gentle vertical float for the machine — a few pixels, one
          // full up-down-up cycle per loop.
          final floatOffset = math.sin(loopT * 2 * math.pi) * 8.0 * uiScale;

          return Stack(
            fit: StackFit.expand,
            children: [
              _buildBackground(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: heroHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        _buildMapBackdrop(t),
                        _buildParticles(loopT, band: _Band.top),
                        for (final bubble in _bubbles)
                          _buildBubble(bubble, loopT),
                        _buildMachine(t, loopT, pulse, floatOffset, uiScale),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _buildParticles(
                            loopT,
                            band: _Band.bottom,
                          ),
                        ),
                        Center(
                          child: _buildText(t, loopT, theme, uiScale),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 28 * uiScale),
                ],
              ),
              // Painted last so it layers on top of the machine, logo,
              // title and tagline — this is what lets the outro read
              // as bubbles gradually engulfing the whole splash rather
              // than sitting behind it.
              _buildBubbleOutro(t),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------
  // Background
  // ---------------------------------------------------------------

  Widget _buildBackground() {
    // White → very light cyan → soft sky-blue, per the reference:
    // bright and airy rather than the previous dark-navy treatment.
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _Palette.bgWhite,
            _Palette.bgCyanTint,
            _Palette.bgSkyBlue,
          ],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
    );
  }

  Widget _buildMapBackdrop(double t) {
    final mapT = _mapIn.transform(t).clamp(0.0, 1.0);
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: mapT,
          child: CustomPaint(
            painter: _MapBackdropPainter(buildings: _buildings),
          ),
        ),
      ),
    );
  }

  Widget _buildParticles(double loopT, {required _Band band}) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ParticlePainter(
          particles: _particles,
          t: loopT,
          band: band,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Bubbles (ambient — small, continuous, confined to the hero band)
  // ---------------------------------------------------------------

  Widget _buildBubble(_BubbleSpec bubble, double loopT) {
    final p = (loopT * bubble.speed + bubble.phase) % 1.0;
    final dy = 0.62 - p * 1.7;
    final sway = math.sin(p * math.pi * 2 + bubble.phase * 10) * bubble.wobble;
    final opacity = (math.sin(p * math.pi)).clamp(0.0, 1.0);
    final scale = 0.75 + 0.45 * math.sin(p * math.pi);

    Widget bubbleWidget = Container(
      width: bubble.size,
      height: bubble.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.35),
          colors: [
            Colors.white.withValues(alpha: 0.95),
            _Palette.cyanGlow.withValues(alpha: 0.35),
            _Palette.cyanAccent.withValues(alpha: 0.08),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: _Palette.iceBlue.withValues(alpha: 0.35),
          width: 0.6,
        ),
      ),
    );

    if (bubble.blur > 0.15) {
      bubbleWidget = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: bubble.blur,
          sigmaY: bubble.blur,
        ),
        child: bubbleWidget,
      );
    }

    return Align(
      alignment: Alignment(bubble.dx + sway, dy),
      child: Opacity(
        opacity: opacity * 0.8,
        child: Transform.scale(scale: scale, child: bubbleWidget),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Bubble outro (dense, one-shot, full-screen — final 1–1.2s)
  // ---------------------------------------------------------------

  /// Full-screen, pointer-transparent layer that paints the dense
  /// outro bubble population. Draws nothing before [_outroStart], so
  /// it costs nothing for the first ~4.8s of the splash.
  Widget _buildBubbleOutro(double t) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _BubbleOutroPainter(bubbles: _outroBubbles, t: t),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Machine
  // ---------------------------------------------------------------

  Widget _buildMachine(
    double t,
    double loopT,
    double pulse,
    double floatOffset,
    double uiScale,
  ) {
    final appearT = _machineIn.transform(t);
    final scale = (0.72 + 0.28 * appearT) * uiScale;
    final opacity = appearT.clamp(0.0, 1.0);
    final spinAngle = loopT * 4 * math.pi; // two drum rotations per loop
    // The float only becomes visible as the machine finishes arriving,
    // so it never fights the entrance scale/fade.
    final floatY = floatOffset * appearT;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, floatY),
        child: Transform.scale(
          scale: scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(210, 218),
                painter: _WashingMachinePainter(
                  spinAngle: spinAngle,
                  pulse: pulse,
                ),
              ),
              const SizedBox(height: 6),
              // Soft grounding shadow, blurred — and it breathes very
              // slightly opposite the float so the machine reads as
              // truly lifting off it, not just sliding up in place.
              Transform.scale(
                scale: 1.0 - (floatY.abs() / 260).clamp(0.0, 0.12),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 5),
                  child: Container(
                    width: 128,
                    height: 16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: _Palette.navyDeep.withValues(alpha: 0.22),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Logo + wordmark
  // ---------------------------------------------------------------

  Widget _buildText(double t, double loopT, ThemeData theme, double uiScale) {
    final logoT = _logoIn.transform(t).clamp(0.0, 1.0);
    final titleT = _titleIn.transform(t).clamp(0.0, 1.0);
    final taglineT = _taglineIn.transform(t).clamp(0.0, 1.0);

    // Continuous, subtle vertical "jump": normal → up → normal → down
    // → normal is exactly what a sine cycle already looks like, so we
    // ride it directly rather than hand-building a bounce curve. Title
    // and tagline use different whole-cycle counts per loop (so the
    // `repeat()` wrap stays seamless) and a phase offset, so the two
    // never look synchronized.
    final titleJump =
        math.sin(loopT * 2 * math.pi * 2) * 4.5 * uiScale * titleT;
    final taglineJump =
        math.sin(loopT * 2 * math.pi * 3 + math.pi / 3) *
        3.0 *
        uiScale *
        taglineT;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32 * uiScale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: 0.7 + 0.3 * logoT,
            child: Opacity(
              opacity: logoT,
              child: _SplashLogoBadge(uiScale: uiScale),
            ),
          ),
          SizedBox(height: 20 * uiScale),
          Opacity(
            opacity: titleT,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - titleT) + titleJump),
              child: Text(
                // AppConstants.appName already resolves to "Laundry
                // Management System" — kept as the single source of
                // truth rather than hardcoding the string here.
                AppConstants.appName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: _Palette.navyDeep,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.15,
                  fontSize: (theme.textTheme.headlineMedium?.fontSize ?? 26) *
                      uiScale.clamp(0.85, 1.05),
                ),
              ),
            ),
          ),
          SizedBox(height: 10 * uiScale),
          Opacity(
            opacity: taglineT,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - taglineT) + taglineJump),
              child: Text(
                'Effortless laundry care, delivered to your door.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _Palette.navyDeep.withValues(alpha: 0.68),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Specs
// =====================================================================

/// One rising soap bubble's fixed parameters. Computed once in
/// [State.initState] so bubbles don't re-randomize on every rebuild.
class _BubbleSpec {
  const _BubbleSpec({
    required this.dx,
    required this.size,
    required this.speed,
    required this.phase,
    required this.blur,
    required this.wobble,
  });

  /// Horizontal position within the hero, roughly -0.6..0.6.
  final double dx;

  /// Diameter in logical pixels.
  final double size;

  /// Cycles per loop revolution.
  final double speed;

  /// Where in its cycle this bubble starts, so they don't all rise in
  /// lockstep.
  final double phase;

  /// Gaussian blur sigma — a few bubbles read slightly out of focus
  /// for depth.
  final double blur;

  /// Amplitude of horizontal sway as the bubble rises.
  final double wobble;
}

/// One background twinkle particle for ambient depth.
class _ParticleSpec {
  const _ParticleSpec({
    required this.dx,
    required this.dy,
    required this.size,
    required this.speed,
    required this.phase,
  });

  final double dx;
  final double dy;
  final double size;
  final double speed;
  final double phase;
}

/// One faint "building" block in the delivery-map backdrop.
class _BuildingSpec {
  const _BuildingSpec({
    required this.dx,
    required this.dy,
    required this.width,
    required this.height,
  });

  /// Fractional position within the map layer, 0..1.
  final double dx;
  final double dy;
  final double width;
  final double height;
}

/// Which half of the splash a particle layer belongs to, so density
/// and size can differ between the busier hero and the calmer text
/// area beneath it.
enum _Band { top, bottom }

/// Which side of the screen one outro bubble rises in from.
enum _BubbleEdge { bottom, left, right }

/// Visual treatment for one outro bubble — mirrors the brief's
/// "tiny/small/medium/large, transparent/white/light-cyan/teal-glow"
/// mixture rather than a single reused bubble look.
enum _BubbleColorVariant { transparent, white, cyanLight, tealGlow }

/// One outro bubble's fixed parameters, computed once in
/// [State.initState]. Unlike [_BubbleSpec] (which loops for all 6s),
/// each of these plays exactly once, timed against [spawnT] on
/// [_SplashScreenState]'s main 0..1 controller — never against the
/// repeating loop controller.
class _OutroBubbleSpec {
  const _OutroBubbleSpec({
    required this.spawnT,
    required this.durationFraction,
    required this.edge,
    required this.targetDx,
    required this.targetDy,
    required this.baseSize,
    required this.depth,
    required this.wobbleAmp,
    required this.wobbleFreq,
    required this.wobblePhase,
    required this.variant,
  });

  /// Point on the *main* controller's 0..1 timeline (not the loop
  /// controller) at which this bubble starts rising. Distributed so
  /// more bubbles have later `spawnT`s, which is what makes the
  /// bubble count read as accelerating toward the end rather than
  /// arriving at a constant rate.
  final double spawnT;

  /// How much of the remaining 0..1 timeline this bubble takes to
  /// rise from its edge to its resting spot and reach full size/
  /// opacity.
  final double durationFraction;

  /// Which edge of the screen this bubble rises in from.
  final _BubbleEdge edge;

  /// Resting position, fraction of screen width/height.
  final double targetDx;
  final double targetDy;

  /// Full-grown diameter in logical pixels.
  final double baseSize;

  /// 0 = small/background/soft-focus, 1 = large/foreground/sharp —
  /// drives both size bias and blur, for the "largest bubbles appear
  /// closer to the viewer" parallax cue.
  final double depth;

  final double wobbleAmp;
  final double wobbleFreq;
  final double wobblePhase;

  final _BubbleColorVariant variant;
}

// =====================================================================
// Palette
// =====================================================================

/// Bright, premium laundry-delivery palette: white/cyan/sky-blue
/// background, deep-navy typography, cyan/teal highlights, and light
/// metallic + dark-navy-glass tones for the machine itself.
class _Palette {
  _Palette._();

  // --- Background ---------------------------------------------------
  static const Color bgWhite = Color(0xFFFFFFFF);
  static const Color bgCyanTint = Color(0xFFEAF6FB);
  static const Color bgSkyBlue = Color(0xFFD3E9F5);

  // --- Typography / deep navy ----------------------------------------
  static const Color navyDeep = Color(0xFF0B2036);
  static const Color navyBlue = Color(0xFF12314C);

  // --- Glow / accent ----------------------------------------------
  static const Color cyanAccent = Color(0xFF1D8DAE);
  static const Color cyanGlow = Color(0xFF56ADC9);
  static const Color tealSecondary = Color(0xFF164C72);

  // --- Metal / glass ------------------------------------------------
  static const Color metalShadow = Color(0xFF9FB4C2);
  static const Color iceBlue = Color(0xFF5B98AA);
  static const Color softWhite = Color(0xFFFFFFFF);
  static const Color softWhiteDim = Color(0xFFE7F0F4);

  // --- Map backdrop --------------------------------------------------
  static const Color mapLine = Color(0xFF9CC3D6);
  static const Color mapFill = Color(0xFFBFE0EE);
}

// =====================================================================
// Particle painter (twinkling dust, top hero band vs. calmer bottom)
// =====================================================================

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.particles,
    required this.t,
    required this.band,
  });

  final List<_ParticleSpec> particles;
  final double t;
  final _Band band;

  @override
  void paint(Canvas canvas, Size size) {
    final baseAlpha = band == _Band.top ? 0.55 : 0.35;
    for (final p in particles) {
      final drift = (t * p.speed + p.phase) % 1.0;
      final y = (p.dy - drift * 0.3) % 1.0 * size.height;
      final x = (p.dx + 0.02 * math.sin(drift * 2 * math.pi)) * size.width;
      final opacity = (math.sin(drift * math.pi)).clamp(0.0, 1.0) * baseAlpha;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);

      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.t != t;
}

// =====================================================================
// Bubble outro painter — the dense, one-shot, full-screen "bubble
// curtain" for the final ~1–1.2s of the splash. Entirely separate
// from [_ParticlePainter]/the ambient bubbles: this one is keyed to
// the main controller's 0..1 progress, not the repeating loop.
// =====================================================================

class _BubbleOutroPainter extends CustomPainter {
  _BubbleOutroPainter({required this.bubbles, required this.t});

  final List<_OutroBubbleSpec> bubbles;

  /// Main splash controller's value, 0..1 across the full 6s.
  final double t;

  /// Matches [_SplashScreenState._outroStart] — nothing in this
  /// painter can be visible before this point, so bail out early for
  /// the first ~4.8s rather than walking the whole bubble list.
  static const _outroStart = 0.80;

  @override
  void paint(Canvas canvas, Size size) {
    if (t < _outroStart) return;

    for (final b in bubbles) {
      if (t < b.spawnT) continue;
      final localT = ((t - b.spawnT) / b.durationFraction).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(localT);

      final targetX = b.targetDx * size.width;
      final targetY = b.targetDy * size.height;

      double startX;
      double startY;
      switch (b.edge) {
        case _BubbleEdge.bottom:
          startX = targetX;
          startY = size.height + b.baseSize;
        case _BubbleEdge.left:
          startX = -b.baseSize;
          startY = targetY;
        case _BubbleEdge.right:
          startX = size.width + b.baseSize;
          startY = targetY;
      }

      // Gentle horizontal drift as each bubble rises, on top of its
      // straight-line path to its resting spot — this is what keeps
      // 90 bubbles from reading as 90 bubbles moving in lockstep.
      final sway = math.sin(localT * b.wobbleFreq * math.pi * 2 + b.wobblePhase) *
          b.wobbleAmp *
          size.width;

      final x = (ui.lerpDouble(startX, targetX, eased) ?? targetX) + sway * eased;
      final y = ui.lerpDouble(startY, targetY, eased) ?? targetY;

      // Grows in rather than appearing full-size, and fades in with
      // the same curve — a bubble is never both fully opaque and
      // still small, which is what would read as "popping in".
      final currentSize = b.baseSize * (0.25 + 0.75 * eased);
      final opacity = Curves.easeOut.transform(localT) * (0.55 + 0.45 * b.depth);

      _drawBubble(canvas, Offset(x, y), currentSize, opacity, b);
    }

    _drawFinalWash(canvas, size);
  }

  void _drawBubble(
    Canvas canvas,
    Offset center,
    double diameter,
    double opacity,
    _OutroBubbleSpec b,
  ) {
    if (opacity <= 0 || diameter <= 0) return;

    final radius = diameter / 2;
    // Background/small bubbles read slightly out of focus; the
    // largest foreground bubbles stay crisp — the depth/parallax cue
    // from the brief.
    final blurSigma = (1.0 - b.depth) * 3.0 + 0.4;

    final List<Color> colors;
    switch (b.variant) {
      case _BubbleColorVariant.transparent:
        colors = [
          Colors.white.withValues(alpha: 0.55 * opacity),
          Colors.white.withValues(alpha: 0.10 * opacity),
          Colors.white.withValues(alpha: 0.0),
        ];
      case _BubbleColorVariant.white:
        colors = [
          Colors.white.withValues(alpha: 0.95 * opacity),
          Colors.white.withValues(alpha: 0.55 * opacity),
          _Palette.softWhiteDim.withValues(alpha: 0.15 * opacity),
        ];
      case _BubbleColorVariant.cyanLight:
        colors = [
          Colors.white.withValues(alpha: 0.85 * opacity),
          _Palette.cyanGlow.withValues(alpha: 0.45 * opacity),
          _Palette.cyanAccent.withValues(alpha: 0.10 * opacity),
        ];
      case _BubbleColorVariant.tealGlow:
        colors = [
          _Palette.cyanGlow.withValues(alpha: 0.75 * opacity),
          _Palette.tealSecondary.withValues(alpha: 0.40 * opacity),
          _Palette.tealSecondary.withValues(alpha: 0.0),
        ];
    }

    final bubbleRect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          colors: colors,
          stops: const [0.0, 0.6, 1.0],
        ).createShader(bubbleRect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
    );

    // Thin glass rim.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (radius * 0.05).clamp(0.4, 2.2),
    );

    // Small specular highlight dot — the "glass-like highlight" cue,
    // only worth drawing once the bubble is big enough to show it.
    if (radius > 4) {
      canvas.drawCircle(
        Offset(center.dx - radius * 0.32, center.dy - radius * 0.32),
        radius * 0.16,
        Paint()..color = Colors.white.withValues(alpha: 0.55 * opacity),
      );
    }
  }

  /// Soft, late-arriving wash that ties the bubble curtain together
  /// right before navigation — "the final 0.2–0.3 seconds should use
  /// the bubbles as a soft transition layer before navigating".
  /// 0.94..1.0 on the main controller is the last ~0.36s of 6s, so
  /// this stays subtle for most of that and only closes in right at
  /// the very end.
  void _drawFinalWash(Canvas canvas, Size size) {
    final washT = ((t - 0.94) / 0.06).clamp(0.0, 1.0);
    if (washT <= 0) return;

    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            _Palette.bgCyanTint.withValues(alpha: 0.55 * washT),
            Colors.white.withValues(alpha: 0.85 * washT),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleOutroPainter oldDelegate) =>
      oldDelegate.t != t;
}

// =====================================================================
// Map backdrop painter — a very faint, static-feeling delivery map:
// building blocks, a dashed route, and two location markers. Drawn
// entirely with primitives so no map image/asset is required.
// =====================================================================

class _MapBackdropPainter extends CustomPainter {
  _MapBackdropPainter({required this.buildings});

  final List<_BuildingSpec> buildings;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawBuildings(canvas, size);
    _drawRoute(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _Palette.mapLine.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    const step = 34.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawBuildings(Canvas canvas, Size size) {
    final fillPaint = Paint()..color = _Palette.mapFill.withValues(alpha: 0.35);
    final strokePaint = Paint()
      ..color = _Palette.mapLine.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final b in buildings) {
      // Keep buildings out of dead-center so they frame, rather than
      // sit under, the machine.
      final biasedDx = b.dx < 0.5 ? b.dx * 0.7 : 0.55 + (b.dx - 0.5) * 0.9;
      final rect = Rect.fromLTWH(
        biasedDx * size.width,
        b.dy * size.height,
        b.width,
        b.height,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, strokePaint);
    }
  }

  void _drawRoute(Canvas canvas, Size size) {
    final start = Offset(size.width * 0.20, size.height * 0.78);
    final mid1 = Offset(size.width * 0.30, size.height * 0.55);
    final mid2 = Offset(size.width * 0.62, size.height * 0.42);
    final end = Offset(size.width * 0.78, size.height * 0.18);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(mid1.dx, mid1.dy)
      ..lineTo(mid2.dx, mid2.dy)
      ..lineTo(end.dx, end.dy);

    _drawDashedPath(
      canvas,
      path,
      Paint()
        ..color = _Palette.cyanAccent.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
      dashLength: 5,
      gapLength: 5,
    );

    // Home marker at the route's start.
    _drawHomePin(canvas, start);
    // "You are here" marker partway along the route.
    _drawLocationDot(canvas, mid1);
    // Destination pin at the route's end.
    _drawDropPin(canvas, end);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final next = distance + (draw ? dashLength : gapLength);
        if (draw) {
          canvas.drawPath(
            metric.extractPath(distance, math.min(next, metric.length)),
            paint,
          );
        }
        distance = next;
        draw = !draw;
      }
    }
  }

  void _drawHomePin(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      12,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      center,
      12,
      Paint()
        ..color = _Palette.navyBlue.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    final housePath = Path()
      ..moveTo(center.dx - 5, center.dy + 4)
      ..lineTo(center.dx - 5, center.dy - 1)
      ..lineTo(center.dx, center.dy - 6)
      ..lineTo(center.dx + 5, center.dy - 1)
      ..lineTo(center.dx + 5, center.dy + 4)
      ..close();
    canvas.drawPath(
      housePath,
      Paint()..color = _Palette.navyDeep.withValues(alpha: 0.55),
    );
  }

  void _drawLocationDot(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      10,
      Paint()..color = _Palette.cyanAccent.withValues(alpha: 0.14),
    );
    canvas.drawCircle(
      center,
      5,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      center,
      5,
      Paint()
        ..color = _Palette.cyanAccent.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(
      center,
      2,
      Paint()..color = _Palette.cyanAccent.withValues(alpha: 0.6),
    );
  }

  void _drawDropPin(Canvas canvas, Offset tip) {
    final pinCenter = Offset(tip.dx, tip.dy - 8);
    final pinPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(
        tip.dx - 8,
        tip.dy - 10,
        tip.dx,
        tip.dy - 16,
      )
      ..quadraticBezierTo(
        tip.dx + 8,
        tip.dy - 10,
        tip.dx,
        tip.dy,
      )
      ..close();
    canvas.drawPath(
      pinPath,
      Paint()..color = _Palette.cyanAccent.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      pinCenter,
      2.6,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _MapBackdropPainter oldDelegate) => false;
}

// =====================================================================
// Logo badge
// =====================================================================

/// Small circular app mark above the wordmark — clean white face,
/// thin navy/cyan ring, soft glow, laundry icon centered inside.
class _SplashLogoBadge extends StatelessWidget {
  const _SplashLogoBadge({required this.uiScale});

  final double uiScale;

  @override
  Widget build(BuildContext context) {
    final diameter = 64.0 * uiScale;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _Palette.softWhite,
        border: Border.all(
          color: _Palette.navyDeep.withValues(alpha: 0.55),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: _Palette.cyanGlow.withValues(alpha: 0.45),
            blurRadius: 16,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: _Palette.navyDeep.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        Icons.local_laundry_service_rounded,
        color: _Palette.navyDeep,
        size: 26 * uiScale,
      ),
    );
  }
}

// =====================================================================
// Washing machine painter — light metallic body, dark-navy glass door,
// realistic-leaning highlights, built entirely from gradients / shadows
// / paths so no external art asset is needed.
// =====================================================================

class _WashingMachinePainter extends CustomPainter {
  _WashingMachinePainter({required this.spinAngle, required this.pulse});

  /// Current drum rotation, radians.
  final double spinAngle;

  /// 0..1 breathing value used to pulse the cyan glow / highlights.
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 4),
      width: 186,
      height: 194,
    );
    final bodyRRect =
        RRect.fromRectAndRadius(bodyRect, const Radius.circular(26));

    _paintAmbientGlow(canvas, bodyRect);
    _paintCastShadow(canvas, bodyRRect);
    _paintBody(canvas, bodyRRect);
    _paintControlStrip(canvas, bodyRect);
    _paintFeet(canvas, bodyRect);

    final drumCenter = Offset(bodyRect.center.dx, bodyRect.center.dy + 20);
    const drumRadius = 58.0;

    _paintDrumBezel(canvas, drumCenter, drumRadius);
    _paintDrumGlassAndContents(canvas, drumCenter, drumRadius);
    _paintGlassHighlights(canvas, drumCenter, drumRadius);
  }

  void _paintAmbientGlow(Canvas canvas, Rect bodyRect) {
    // Soft cyan halo behind the whole machine — reads as the "soft
    // cyan glow around the machine" from the brief without ever
    // overpowering the light body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bodyRect.inflate(18),
        const Radius.circular(40),
      ),
      Paint()
        ..color = _Palette.cyanGlow.withValues(alpha: 0.10 + 0.08 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );
  }

  void _paintCastShadow(Canvas canvas, RRect bodyRRect) {
    final shadowPaint = Paint()
      ..color = _Palette.navyDeep.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawRRect(bodyRRect.shift(const Offset(0, 10)), shadowPaint);
  }

  void _paintBody(Canvas canvas, RRect bodyRRect) {
    // Light, brushed-metal body: soft white to a pale ice-blue
    // falloff, so it reads as pale and premium rather than flat white.
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _Palette.softWhite,
          _Palette.softWhiteDim,
          _Palette.metalShadow.withValues(alpha: 0.55),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(bodyRRect.outerRect);
    canvas.drawRRect(bodyRRect, bodyPaint);

    // Vertical specular sweep — the "subtle cyan reflections" cue,
    // tinted cyan rather than plain white so it feels branded.
    final sweepRect = Rect.fromLTWH(
      bodyRRect.left + bodyRRect.width * 0.62,
      bodyRRect.top,
      bodyRRect.width * 0.20,
      bodyRRect.height,
    );
    canvas.save();
    canvas.clipRRect(bodyRRect);
    canvas.drawRect(
      sweepRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _Palette.cyanGlow.withValues(alpha: 0.35 + 0.15 * pulse),
            _Palette.cyanGlow.withValues(alpha: 0.02),
          ],
        ).createShader(sweepRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.restore();

    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..color = _Palette.navyDeep.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _paintControlStrip(Canvas canvas, Rect bodyRect) {
    // Dark navy control strip along the top — the strongest visual
    // anchor tying the light body to the dark glass door below it.
    final stripRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        bodyRect.left + 10,
        bodyRect.top + 10,
        bodyRect.width - 20,
        26,
      ),
      const Radius.circular(13),
    );
    canvas.drawRRect(
      stripRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_Palette.navyBlue, _Palette.navyDeep],
        ).createShader(stripRect.outerRect),
    );

    // Small indicator light.
    final dotCenter = Offset(stripRect.left + 16, stripRect.center.dy);
    canvas.drawCircle(
      dotCenter,
      4.4,
      Paint()
        ..color = _Palette.cyanGlow.withValues(alpha: 0.7 + 0.3 * pulse),
    );

    // Three faint setting dots.
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(stripRect.left + 36 + i * 12, stripRect.center.dy),
        2.0,
        Paint()..color = Colors.white.withValues(alpha: 0.30),
      );
    }

    // Slim display/slot on the right.
    final slotRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        stripRect.right - 46,
        stripRect.center.dy - 3.5,
        34,
        7,
      ),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(
      slotRect,
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
  }

  void _paintFeet(Canvas canvas, Rect bodyRect) {
    final feetPaint = Paint()
      ..color = _Palette.metalShadow.withValues(alpha: 0.6);
    for (final dx in [bodyRect.left + 12, bodyRect.right - 26]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(dx, bodyRect.bottom - 5, 14, 9),
          const Radius.circular(4),
        ),
        feetPaint,
      );
    }
  }

  void _paintDrumBezel(Canvas canvas, Offset drumCenter, double drumRadius) {
    // Outer light-metal ring, then the dark navy bezel that frames the
    // glass — this dark ring is what makes the door read as "glass"
    // against the light body, mirroring the reference image.
    canvas.drawCircle(
      drumCenter,
      drumRadius + 12,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Palette.softWhite, _Palette.softWhiteDim],
        ).createShader(
          Rect.fromCircle(center: drumCenter, radius: drumRadius + 12),
        ),
    );
    canvas.drawCircle(
      drumCenter,
      drumRadius + 12,
      Paint()
        ..color = _Palette.navyDeep.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      drumCenter,
      drumRadius + 6,
      Paint()
        ..shader = RadialGradient(
          colors: [_Palette.navyBlue, _Palette.navyDeep],
        ).createShader(
          Rect.fromCircle(center: drumCenter, radius: drumRadius + 6),
        ),
    );
  }

  void _paintDrumGlassAndContents(
    Canvas canvas,
    Offset drumCenter,
    double drumRadius,
  ) {
    // Deep navy glass interior with a cyan sheen toward the light
    // source, upper-left.
    canvas.drawCircle(
      drumCenter,
      drumRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [
            _Palette.tealSecondary.withValues(alpha: 0.55),
            _Palette.navyBlue,
            _Palette.navyDeep,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: drumCenter, radius: drumRadius)),
    );

    canvas.save();
    canvas.clipPath(
      Path()
        ..addOval(Rect.fromCircle(center: drumCenter, radius: drumRadius - 3)),
    );
    _drawSuds(canvas, drumCenter, drumRadius);
    _drawTumblingClothes(canvas, drumCenter, drumRadius, spinAngle);
    canvas.restore();
  }

  void _drawSuds(Canvas canvas, Offset drumCenter, double radius) {
    // A soft, slowly-shifting suds pool along the bottom of the drum.
    final wobble = math.sin(spinAngle * 0.5) * 3;
    final waterRect =
        Rect.fromCircle(center: drumCenter, radius: radius).translate(0, wobble);
    canvas.drawArc(
      waterRect,
      0.30,
      math.pi - 0.6,
      false,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );

    final foamRandom = math.Random(3);
    for (var i = 0; i < 8; i++) {
      final angle = 0.35 + foamRandom.nextDouble() * (math.pi - 0.7);
      final r = radius * (0.7 + foamRandom.nextDouble() * 0.22);
      final p = Offset(
        drumCenter.dx + math.cos(angle) * r,
        drumCenter.dy + math.sin(angle) * r + wobble * 0.4,
      );
      canvas.drawCircle(
        p,
        1.3 + foamRandom.nextDouble() * 1.5,
        Paint()..color = Colors.white.withValues(alpha: 0.32),
      );
    }
  }

  void _drawTumblingClothes(
    Canvas canvas,
    Offset drumCenter,
    double radius,
    double spinAngle,
  ) {
    final colors = [
      _Palette.cyanGlow,
      Colors.white.withValues(alpha: 0.85),
      _Palette.cyanAccent,
      _Palette.iceBlue,
    ];

    for (var i = 0; i < 4; i++) {
      final angle = spinAngle + i * (2 * math.pi / 4);
      final orbit = radius * 0.42;
      final blobCenter = Offset(
        drumCenter.dx + math.cos(angle) * orbit,
        drumCenter.dy + math.sin(angle) * orbit * 0.72,
      );

      canvas.save();
      canvas.translate(blobCenter.dx, blobCenter.dy);
      canvas.rotate(angle);

      final blobPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            colors[i % colors.length],
            colors[i % colors.length].withValues(alpha: 0.6),
          ],
        ).createShader(const Rect.fromLTWH(-14, -12, 28, 24));

      final blobPath = Path()
        ..moveTo(-13, 0)
        ..quadraticBezierTo(-9, -11, 2, -9)
        ..quadraticBezierTo(13, -8, 11, 3)
        ..quadraticBezierTo(9, 11, -4, 9)
        ..quadraticBezierTo(-13, 8, -13, 0)
        ..close();
      canvas.drawPath(blobPath, blobPaint);

      canvas.restore();
    }
  }

  void _paintGlassHighlights(
    Canvas canvas,
    Offset drumCenter,
    double drumRadius,
  ) {
    // Outer rim highlight.
    canvas.drawCircle(
      drumCenter,
      drumRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Curved specular streak, upper-left — subtly drifts with the
    // pulse so the reflection feels alive rather than painted-on.
    final drift = math.sin(pulse * math.pi) * 3;
    final rect = Rect.fromCircle(center: drumCenter, radius: drumRadius);
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    final streakPath = Path()
      ..moveTo(
        rect.left + drumRadius * 0.22 + drift,
        rect.top + drumRadius * 0.35,
      )
      ..quadraticBezierTo(
        rect.left + drumRadius * 0.55 + drift,
        rect.top + drumRadius * 0.05,
        rect.left + drumRadius * 0.95 + drift,
        rect.top + drumRadius * 0.35,
      )
      ..lineTo(
        rect.left + drumRadius * 0.85 + drift,
        rect.top + drumRadius * 0.52,
      )
      ..quadraticBezierTo(
        rect.left + drumRadius * 0.55 + drift,
        rect.top + drumRadius * 0.26,
        rect.left + drumRadius * 0.32 + drift,
        rect.top + drumRadius * 0.52,
      )
      ..close();
    canvas.drawPath(
      streakPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.drawCircle(
      Offset(
        drumCenter.dx + drumRadius * 0.5,
        drumCenter.dy + drumRadius * 0.5,
      ),
      drumRadius * 0.12,
      Paint()
        ..color = _Palette.cyanGlow.withValues(alpha: 0.25 + 0.15 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WashingMachinePainter oldDelegate) =>
      oldDelegate.spinAngle != spinAngle || oldDelegate.pulse != pulse;
}