import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// עריכה מקומית בפסקת מקור, ללא היסטים או עוגנים של נוסח אחר.
class PluginCorrectionParagraph extends StatefulWidget {
  final String tabId;
  final int sectionIndex;
  final String sourceText;
  final RenderSettings settings;
  final Widget original;
  final PluginCorrectionSessionService? service;
  final bool sessionActive;

  const PluginCorrectionParagraph({
    super.key,
    required this.tabId,
    required this.sectionIndex,
    required this.sourceText,
    required this.settings,
    required this.original,
    this.service,
    this.sessionActive = false,
  });

  @override
  State<PluginCorrectionParagraph> createState() =>
      _PluginCorrectionParagraphState();
}

class _PluginCorrectionParagraphState extends State<PluginCorrectionParagraph> {
  bool _editable = false;
  bool _corrected = false;
  TextEditingController? _controller;
  FocusNode? _focus;
  String? _lastRejection;
  DateTime _lastRejectionAt = DateTime.fromMillisecondsSinceEpoch(0);
  PluginCorrectionSessionService get _registry =>
      widget.service ?? PluginCorrectionSessionService.instance;

  @override
  void initState() {
    super.initState();
    if (widget.sessionActive) _activate();
  }

  @override
  void didUpdateWidget(PluginCorrectionParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serviceChanged = oldWidget.service != widget.service;
    if (oldWidget.sessionActive && (!widget.sessionActive || serviceChanged)) {
      (oldWidget.service ?? PluginCorrectionSessionService.instance)
          .removeListener(_changed);
      if (!widget.sessionActive || serviceChanged) _disposeEditor();
    }
    if (widget.sessionActive && (!oldWidget.sessionActive || serviceChanged)) {
      _activate();
    }
    if (widget.sessionActive) _syncText();
  }

  void _activate() {
    _controller = TextEditingController();
    _focus = FocusNode();
    _registry.addListener(_changed);
    _syncText();
  }

  void _disposeEditor() {
    _controller?.dispose();
    _focus?.dispose();
    _controller = null;
    _focus = null;
    _editable = false;
    _corrected = false;
  }

  bool _syncText() {
    if (!_registry.hasSessionForTab(widget.tabId)) return false;
    final controller = _controller;
    if (controller == null) return false;
    final text = _registry.editableText(
      widget.tabId,
      widget.sectionIndex,
      widget.sourceText,
    );
    if (controller.text == text) return false;
    final selection = controller.selection;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.isValid
            ? selection.extentOffset.clamp(0, text.length)
            : text.length,
      ),
    );
    return true;
  }

  bool get _isCorrected => _registry.isCorrected(
    widget.tabId,
    widget.sectionIndex,
    widget.sourceText,
  );

  void _changed() {
    if (!mounted) return;
    final textChanged = _syncText();
    final editable = _registry.canEditParagraph(
      widget.tabId,
      widget.sourceText,
    );
    final corrected = _isCorrected;
    if (!textChanged && editable == _editable && corrected == _corrected) {
      return;
    }
    _editable = editable;
    _corrected = corrected;
    setState(() {});
  }

  /// מקש שנדחה שוב ושוב (למשל בגבול הגודל) לא מציף הודעה ורטט בכל הקשה.
  void _showRejection(PluginCorrectionException error) {
    final now = DateTime.now();
    if (_lastRejection == error.message &&
        now.difference(_lastRejectionAt) < const Duration(seconds: 3)) {
      return;
    }
    _lastRejection = error.message;
    _lastRejectionAt = now;
    UiSnack.showError(PluginMessages.correctionEditRejected(error.message));
  }

  TextEditingValue _validate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    try {
      _registry.validateNativeEdit(
        widget.tabId,
        widget.sectionIndex,
        widget.sourceText,
        newValue.text,
      );
      return newValue;
    } on PluginCorrectionException catch (error) {
      _showRejection(error);
      return oldValue;
    }
  }

  void _applyText(String text) {
    try {
      _registry.editParagraph(
        widget.tabId,
        widget.sectionIndex,
        widget.sourceText,
        text,
      );
    } on PluginCorrectionException catch (error) {
      _showRejection(error);
      _syncText();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.sessionActive) return widget.original;
    _editable = _registry.canEditParagraph(widget.tabId, widget.sourceText);
    if (!_editable) {
      return widget.original;
    }
    _corrected = _isCorrected;
    final colorScheme = Theme.of(context).colorScheme;
    // מבנה קבוע: החלפת העץ בהקשה הראשונה הייתה יוצרת את שדה העריכה מחדש.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: _corrected
              ? BorderSide(
                  color: AppSurfaces.correctedParagraphMarker(colorScheme),
                  width: 3,
                )
              : BorderSide.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8),
        child: _buildEditor(),
      ),
    );
  }

  Widget _buildEditor() {
    final settings = widget.settings;
    return RtlTextField(
      controller: _controller!,
      focusNode: _focus!,
      maxLines: null,
      minLines: 1,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      style: TextStyle(
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
        fontWeight: settings.fontWeight,
        height: settings.lineHeight,
      ),
      inputFormatters: [TextInputFormatter.withFunction(_validate)],
      onChanged: _applyText,
      onSubmitted: (_) => _focus!.unfocus(),
    );
  }

  @override
  void dispose() {
    _registry.removeListener(_changed);
    _controller?.dispose();
    _focus?.dispose();
    super.dispose();
  }
}
