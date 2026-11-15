import { HStack, Image, Spacer, Text, VStack } from "@expo/ui/swift-ui";
import { font, foregroundStyle, padding } from "@expo/ui/swift-ui/modifiers";
import { createLiveActivity, type LiveActivity } from "expo-widgets";
import AReachSpatial from "@/modules/areach-spatial";

export type AReachLiveEventActivityProps = {
	endsAt: number;
	eventId: string;
	status: string;
	title: string;
};

type AReachLiveActivityEnvironment = {
	colorScheme: "light" | "dark";
};

const AReachLiveEventActivityView = (props: AReachLiveEventActivityProps, environment: AReachLiveActivityEnvironment) => {
	"widget";

	const isDark = environment.colorScheme === "dark";
	const accentColor = isDark ? "#63B77A" : "#14664A";
	const primaryTextStyle = { type: "hierarchical", style: "primary" } as const;
	const secondaryTextStyle = { type: "hierarchical", style: "secondary" } as const;

	return {
		banner: (
			<HStack spacing={8} modifiers={[padding({ horizontal: 14, vertical: 10 })]}>
				<Image color={accentColor} systemName="dot.radiowaves.left.and.right" />
				<VStack alignment="leading" spacing={2}>
					<Text modifiers={[font({ weight: "bold", size: 15 }), foregroundStyle(primaryTextStyle)]}>{props.title}</Text>
					<Text modifiers={[font({ size: 12 }), foregroundStyle(secondaryTextStyle)]}>{props.status}</Text>
				</VStack>
				<Spacer />
			</HStack>
		),
		bannerSmall: (
			<HStack spacing={8} modifiers={[padding({ horizontal: 12, vertical: 8 })]}>
				<Image color={accentColor} systemName="dot.radiowaves.left.and.right" />
				<Text modifiers={[font({ weight: "bold", size: 13 }), foregroundStyle(primaryTextStyle)]}>Live nearby detection</Text>
				<Spacer />
			</HStack>
		),
		compactLeading: <Image color={accentColor} systemName="dot.radiowaves.left.and.right" />,
		compactTrailing: <Text modifiers={[font({ weight: "bold", size: 12 }), foregroundStyle(accentColor)]}>Live</Text>,
		minimal: <Image color={accentColor} systemName="dot.radiowaves.left.and.right" />,
		expandedLeading: (
			<VStack modifiers={[padding({ all: 10 })]}>
				<Image color={accentColor} systemName="dot.radiowaves.left.and.right" />
				<Text modifiers={[font({ size: 11 }), foregroundStyle(secondaryTextStyle)]}>Nearby</Text>
			</VStack>
		),
		expandedTrailing: (
			<VStack modifiers={[padding({ all: 10 })]}>
				<Text modifiers={[font({ weight: "bold", size: 15 }), foregroundStyle(accentColor)]}>Live</Text>
			</VStack>
		),
		expandedBottom: (
			<VStack alignment="leading" spacing={2} modifiers={[padding({ horizontal: 12, vertical: 8 })]}>
				<Text modifiers={[font({ weight: "bold", size: 16 }), foregroundStyle(primaryTextStyle)]}>{props.title}</Text>
				<Text modifiers={[font({ size: 12 }), foregroundStyle(secondaryTextStyle)]}>{props.status}</Text>
			</VStack>
		),
	};
};

const AReachLiveEventActivity = createLiveActivity<AReachLiveEventActivityProps>("AReachLiveEventActivity", AReachLiveEventActivityView);

const LIVE_ACTIVITY_VERIFY_ATTEMPTS = 6;
const LIVE_ACTIVITY_VERIFY_INTERVAL_MS = 50;

function getLiveActivityInstances() {
	try {
		return AReachLiveEventActivity.getInstances();
	} catch {
		return [];
	}
}

async function waitForLiveActivity() {
	for (let attempt = 0; attempt < LIVE_ACTIVITY_VERIFY_ATTEMPTS; attempt += 1) {
		const activity = getLiveActivityInstances()[0];
		if (activity) {
			return activity;
		}

		await new Promise((resolve) => setTimeout(resolve, LIVE_ACTIVITY_VERIFY_INTERVAL_MS));
	}

	return undefined;
}

/**
 * ActivityKit start is synchronous in expo-widgets, but the system-owned
 * activity list is not. The native responder is enabled only after the
 * activity is observable as active.
 */
export async function startAReachLiveEventActivity(props: AReachLiveEventActivityProps, url: string) {
	const existingActivity = getLiveActivityInstances()[0];

	try {
		if (existingActivity) {
			await existingActivity.update(props);
		} else {
			AReachLiveEventActivity.start(props, url);
		}

		const activeActivity = await waitForLiveActivity();
		if (!activeActivity) {
			await AReachSpatial.setBackgroundResponderActive(false).catch(() => {});
			return undefined;
		}

		await AReachSpatial.setBackgroundResponderActive(true);
		const responderActive = AReachSpatial.isBackgroundResponderActive();
		if (!responderActive) {
			return undefined;
		}
		return activeActivity;
	} catch (error) {
		await AReachSpatial.setBackgroundResponderActive(false).catch(() => {});
		throw error;
	}
}

export async function stopAReachLiveEventActivities(props?: AReachLiveEventActivityProps) {
	const activities = getLiveActivityInstances();

	await Promise.all(
		activities.map((activity: LiveActivity<AReachLiveEventActivityProps>) => activity.end("immediate", props, new Date()).catch(() => {})),
	);
	await AReachSpatial.setBackgroundResponderActive(false);
}

/** Reconciles the native responder with ActivityKit after a dismissal or wake. */
export async function syncAReachLiveEventActivityState() {
	const activityIsActive = getLiveActivityInstances().length > 0;
	try {
		await AReachSpatial.setBackgroundResponderActive(activityIsActive);
	} catch {
		return false;
	}
	const responderIsActive = AReachSpatial.isBackgroundResponderActive();
	return activityIsActive && responderIsActive;
}

export function getAReachLiveEventActivityState() {
	return {
		activeActivityCount: getLiveActivityInstances().length,
	};
}
