part of '../models.dart';

class ActionSpec {
  ActionSpec({
    required this.id,
    required this.title,
    required this.command,
    this.tooltip,
    this.iconName,
    this.iconEmoji,
    this.iconOnly = false,
    this.role = 'primary',
    this.destructive = false,
    this.visibleWhen = const [],
    this.disabledWhen = const [],
    this.disabledTooltip,
    this.precheck,
    this.confirm,
  });

  final String id;
  final String title;
  final String? tooltip;
  final String? iconName;
  final String? iconEmoji;
  final bool iconOnly;
  final String role;
  final bool destructive;
  final List<ActionConditionSpec> visibleWhen;
  final List<ActionConditionSpec> disabledWhen;
  final String? disabledTooltip;
  final ActionPrecheckSpec? precheck;
  final ActionConfirmationSpec? confirm;
  final CommandSpec command;

  factory ActionSpec.fromJson(Map<String, Object?> json) => ActionSpec(
        id: stringValue(json['id']),
        title: stringValue(json['title']),
        tooltip: optionalString(json['tooltip']),
        iconName: optionalString(json['iconName']) ??
            optionalString(json['systemImage']),
        iconEmoji: optionalString(json['iconEmoji']),
        iconOnly: json['iconOnly'] == true,
        role: optionalString(json['role']) ?? 'primary',
        destructive:
            json['destructive'] == true || json['role'] == 'destructive',
        visibleWhen: listOfMaps(json['visibleWhen'])
            .map(ActionConditionSpec.fromJson)
            .toList(),
        disabledWhen: listOfMaps(json['disabledWhen'])
            .map(ActionConditionSpec.fromJson)
            .toList(),
        disabledTooltip: optionalString(json['disabledTooltip']),
        precheck: json['precheck'] is Map<String, Object?>
            ? ActionPrecheckSpec.fromJson(
                json['precheck']! as Map<String, Object?>)
            : null,
        confirm: json['confirm'] is Map<String, Object?>
            ? ActionConfirmationSpec.fromJson(
                json['confirm']! as Map<String, Object?>)
            : null,
        command: json['command'] is Map<String, Object?>
            ? CommandSpec.fromJson(json['command']! as Map<String, Object?>)
            : const CommandSpec(executable: '', arguments: []),
      );
}

class ActionConditionSpec {
  const ActionConditionSpec({
    required this.placeholder,
    this.equals,
    this.notEquals,
    this.inValues = const [],
    this.notInValues = const [],
    this.exists,
    this.lessThan,
    this.lessThanOrEqual,
    this.greaterThan,
    this.greaterThanOrEqual,
  });

  final String placeholder;
  final String? equals;
  final String? notEquals;
  final List<String> inValues;
  final List<String> notInValues;
  final bool? exists;
  final String? lessThan;
  final String? lessThanOrEqual;
  final String? greaterThan;
  final String? greaterThanOrEqual;

  factory ActionConditionSpec.fromJson(Map<String, Object?> json) =>
      ActionConditionSpec(
        placeholder: stringValue(json['placeholder']),
        equals: optionalString(json['equals']),
        notEquals: optionalString(json['notEquals']),
        inValues: listOfStrings(json['in']),
        notInValues: listOfStrings(json['notIn']),
        exists: json['exists'] is bool ? json['exists']! as bool : null,
        lessThan: optionalString(json['lessThan']),
        lessThanOrEqual: optionalString(json['lessThanOrEqual']),
        greaterThan: optionalString(json['greaterThan']),
        greaterThanOrEqual: optionalString(json['greaterThanOrEqual']),
      );
}

class ActionPrecheckSpec {
  const ActionPrecheckSpec({
    this.diskSpaceGB,
    this.diskSpacePath,
    this.warningMessage,
  });

  final String? diskSpaceGB;
  final String? diskSpacePath;
  final String? warningMessage;

  factory ActionPrecheckSpec.fromJson(Map<String, Object?> json) =>
      ActionPrecheckSpec(
        diskSpaceGB: optionalString(json['diskSpaceGB']),
        diskSpacePath: optionalString(json['diskSpacePath']),
        warningMessage: optionalString(json['warningMessage']),
      );
}

class ActionConfirmationSpec {
  const ActionConfirmationSpec({
    required this.title,
    this.message,
    this.confirmButtonTitle = 'Continue',
    this.cancelButtonTitle = 'Cancel',
    this.requiredText,
    this.prompt,
  });

  final String title;
  final String? message;
  final String confirmButtonTitle;
  final String cancelButtonTitle;
  final String? requiredText;
  final String? prompt;

  factory ActionConfirmationSpec.fromJson(Map<String, Object?> json) =>
      ActionConfirmationSpec(
        title: stringValue(json['title']),
        message: optionalString(json['message']),
        confirmButtonTitle:
            optionalString(json['confirmButtonTitle']) ?? 'Continue',
        cancelButtonTitle:
            optionalString(json['cancelButtonTitle']) ?? 'Cancel',
        requiredText: optionalString(json['requiredText']),
        prompt: optionalString(json['prompt']),
      );
}
