const fs = require("node:fs");
const path = require("node:path");
const xcode = require("xcode");
const { withFinalizedMod, withPodfile } = require("expo/config-plugins");

const WIDGET_TARGET_NAME = "ExpoWidgetsTarget";
const DEV_LAUNCHER_PHASE_NAME = "[Expo Dev Launcher] Strip Local Network Keys for Release";
const TOOLCHAIN_SWIFT_LIBRARY_PATHS = [
	'"$(TOOLCHAIN_DIR)/usr/lib/swift/$(PLATFORM_NAME)"',
	// biome-ignore lint/suspicious/noTemplateCurlyInString: Xcode placeholders must remain literal
	'"${TOOLCHAIN_DIR}/usr/lib/swift/${PLATFORM_NAME}"',
];

function updateTargetVersions(project, targetName, marketingVersion, buildNumber) {
	const target = project.pbxTargetByName(targetName);
	if (!target) {
		return;
	}

	const configurationList = project.pbxXCConfigurationList()[target.buildConfigurationList];
	if (!configurationList) {
		return;
	}

	const configurations = project.pbxXCBuildConfigurationSection();
	for (const configurationReference of configurationList.buildConfigurations) {
		const configuration = configurations[configurationReference.value];
		if (!configuration) {
			continue;
		}

		configuration.buildSettings = configuration.buildSettings ?? {};
		configuration.buildSettings.MARKETING_VERSION = marketingVersion;
		configuration.buildSettings.CURRENT_PROJECT_VERSION = buildNumber;
	}
}

function fixDevLauncherScriptDependencies(project, targetName) {
	const nativeTargetId = project.findTargetKey(targetName ?? "");
	const target = nativeTargetId ? project.pbxNativeTargetSection()[nativeTargetId] : undefined;
	const phaseReference = target?.buildPhases?.find((phase) => phase.comment === DEV_LAUNCHER_PHASE_NAME);
	const phase = phaseReference ? project.hash.project.objects.PBXShellScriptBuildPhase[phaseReference.value] : undefined;

	if (phase) {
		phase.outputPaths = ['"$(DERIVED_FILE_DIR)/areach-strip-local-network-keys.stamp"'];
		phase.alwaysOutOfDate = 1;
		const stampCommand = "touch $SCRIPT_OUTPUT_FILE_0";
		if (!phase.shellScript.includes(stampCommand)) {
			const closingQuoteIndex = phase.shellScript.lastIndexOf('"');
			if (closingQuoteIndex >= 0) {
				phase.shellScript = `${phase.shellScript.slice(0, closingQuoteIndex)}\n\n${stampCommand}\n${phase.shellScript.slice(closingQuoteIndex)}`;
			}
		}
	}
}

function withIosProjectWarningFixes(config) {
	const marketingVersion = String(config.ios?.version ?? config.version ?? "1.0");
	const buildNumber = String(config.ios?.buildNumber ?? "1");

	return withFinalizedMod(config, [
		"ios",
		async (config) => {
			const projectPath = path.join(config.modRequest.platformProjectRoot, `${config.modRequest.projectName}.xcodeproj`, "project.pbxproj");
			if (!fs.existsSync(projectPath)) {
				return config;
			}

			const project = xcode.project(projectPath);
			project.parseSync();
			updateTargetVersions(project, "AReach", marketingVersion, buildNumber);
			updateTargetVersions(project, WIDGET_TARGET_NAME, marketingVersion, buildNumber);
			fixDevLauncherScriptDependencies(project, config.modRequest.projectName);
			fs.writeFileSync(projectPath, project.writeSync());
			return config;
		},
	]);
}

function withPodfileWarningFix(config) {
	return withPodfile(config, (config) => {
		const marker = "# AReach: remove deprecated Xcode Swift toolchain search path";
		if (config.modResults.contents.includes(marker)) {
			return config;
		}

		const postInstallStart = config.modResults.contents.indexOf("post_install do |installer|");
		const postInstallEnd = config.modResults.contents.indexOf("\n  end", postInstallStart);
		if (postInstallStart === -1 || postInstallEnd === -1) {
			return config;
		}

		const cleanup = `

    ${marker}
    # CocoaPods adds this path for older Swift toolchains. Xcode 26 can
    # resolve TOOLCHAIN_DIR to its optional Metal toolchain, which is not a
    # valid Swift library directory for this iOS build.
    Dir.glob(File.join(installer.sandbox.target_support_files_root.to_s, "**", "*.xcconfig")).each do |xcconfig_path|
      contents = File.read(xcconfig_path)
      fixed_contents = contents
        .gsub('${TOOLCHAIN_SWIFT_LIBRARY_PATHS[0]}', "")
        .gsub('${TOOLCHAIN_SWIFT_LIBRARY_PATHS[1]}', "")
      File.write(xcconfig_path, fixed_contents) if fixed_contents != contents
    end`;

		config.modResults.contents = `${config.modResults.contents.slice(0, postInstallEnd)}${cleanup}${config.modResults.contents.slice(postInstallEnd)}`;

		return config;
	});
}

module.exports = (config) => withPodfileWarningFix(withIosProjectWarningFixes(config));
