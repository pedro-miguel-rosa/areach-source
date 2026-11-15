const { withAppDelegate, withInfoPlist } = require("expo/config-plugins");

const SCENE_MANIFEST = {
	UIApplicationSupportsMultipleScenes: false,
	UISceneConfigurations: {
		UIWindowSceneSessionRoleApplication: [
			{
				UISceneConfigurationName: "Default Configuration",
				UISceneDelegateClassName: "EXExpoAppSceneDelegate",
			},
		],
	},
};

function withIosSceneManifest(config) {
	return withInfoPlist(config, (config) => {
		config.modResults.UIApplicationSceneManifest = SCENE_MANIFEST;
		return config;
	});
}

function withSceneAwareAppDelegate(config) {
	return withAppDelegate(config, (config) => {
		if (config.modResults.language !== "swift") {
			throw new Error("AReach requires a Swift AppDelegate for the iOS scene lifecycle.");
		}

		let contents = config.modResults.contents;
		contents = contents.replace(
			/class AppDelegate: ExpoAppDelegate(?!, ExpoReactNativeFactoryProvider)/,
			"class AppDelegate: ExpoAppDelegate, ExpoReactNativeFactoryProvider",
		);

		contents = contents.replace(
			/\n#if os\(iOS\) \|\| os\(tvOS\)[\s\S]*?\n#endif\n\n {4}return super\.application\(/,
			"\n\n    return super.application(",
		);

		config.modResults.contents = contents;
		return config;
	});
}

module.exports = (config) => withSceneAwareAppDelegate(withIosSceneManifest(config));
