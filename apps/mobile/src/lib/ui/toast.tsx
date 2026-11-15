import { useEffect, useRef, useState } from "react";
import { Pressable } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { createStyles } from "@/lib/theme/factories";
import { Column } from "./column";
import { Icon, type IconName } from "./icon";
import { Text } from "./text";
import { View } from "./view";

type ToastTone = "error" | "info" | "success";

type ToastColors = {
	background: string;
	border: string;
	close: string;
	icon: string;
	iconBackground: string;
	message: string;
	title: string;
};

type ToastInput = {
	durationMs?: number;
	error?: unknown;
	message: string;
	title?: string;
	tone?: ToastTone;
};

type Toast = {
	durationMs: number;
	id: string;
	message: string;
	title?: string;
	tone: ToastTone;
};

type ToastListener = (toast: Toast) => void;

const listeners = new Set<ToastListener>();

export function showToast(input: ToastInput) {
	if (input.error) {
		console.error(input.error);
	}

	const toast: Toast = {
		id: createId(),
		message: input.message,
		title: input.title,
		tone: input.tone ?? "info",
		durationMs: input.durationMs ?? 4000,
	};

	for (const listener of listeners) {
		listener(toast);
	}
}

export function Toast() {
	const insets = useSafeAreaInsets();
	const [toasts, setToasts] = useState<Toast[]>([]);
	const timeoutIdsRef = useRef(new Map<string, ReturnType<typeof setTimeout>>());
	const { styles, theme } = useStyles();

	function removeToast(toastId: string) {
		const timeoutId = timeoutIdsRef.current.get(toastId);

		if (timeoutId) {
			clearTimeout(timeoutId);
			timeoutIdsRef.current.delete(toastId);
		}

		setToasts((current) => current.filter((item) => item.id !== toastId));
	}

	useEffect(() => {
		function handleToast(toast: Toast) {
			setToasts((current) => [...current.slice(-2), toast]);

			const timeoutId = setTimeout(() => {
				setToasts((current) => current.filter((item) => item.id !== toast.id));
				timeoutIdsRef.current.delete(toast.id);
			}, toast.durationMs);

			timeoutIdsRef.current.set(toast.id, timeoutId);
		}

		listeners.add(handleToast);

		return () => {
			listeners.delete(handleToast);

			for (const timeoutId of timeoutIdsRef.current.values()) {
				clearTimeout(timeoutId);
			}

			timeoutIdsRef.current.clear();
		};
	}, []);

	if (toasts.length === 0) {
		return null;
	}

	return (
		<View
			pointerEvents="box-none"
			style={[
				styles.viewport,
				{
					paddingBottom: insets.bottom + theme.spacing.md,
				},
			]}
		>
			<Column alignSelf="center" gap="sm" maxWidth={520} width="100%">
				{toasts.map((toast) => {
					const colors = getToastColors(toast.tone, theme);
					const title = toast.title ?? getToastTitle(toast.tone);
					const iconName = getToastIcon(toast.tone);

					return (
						<Pressable
							key={toast.id}
							accessibilityRole="button"
							onPress={() => removeToast(toast.id)}
							style={[
								styles.toast,
								{
									backgroundColor: colors.background,
									borderColor: colors.border,
								},
							]}
						>
							<View
								style={[
									styles.toastIcon,
									{
										backgroundColor: colors.iconBackground,
									},
								]}
							>
								<Icon color={colors.icon} name={iconName} size={18} />
							</View>

							<Column flex gap="xs">
								<Text color={colors.title} size="sm" weight="semibold">
									{title}
								</Text>
								<Text color={colors.message} size="sm">
									{toast.message}
								</Text>
							</Column>

							<Icon color={colors.close} name="xMark" size={16} />
						</Pressable>
					);
				})}
			</Column>
		</View>
	);
}

function getToastColors(tone: ToastTone, theme: ReturnType<typeof useStyles>["theme"]) {
	switch (tone) {
		case "error":
			return {
				background: theme.colors.errorSurface,
				border: theme.colors.errorBorder,
				close: theme.colors.textSecondary,
				icon: theme.colors.error,
				iconBackground: theme.colors.errorMuted,
				message: theme.colors.textSecondary,
				title: theme.colors.error,
			} as const satisfies ToastColors;
		case "success":
			return {
				background: theme.colors.successSurface,
				border: theme.colors.successBorder,
				close: theme.colors.textSecondary,
				icon: theme.colors.success,
				iconBackground: theme.colors.successMuted,
				message: theme.colors.textSecondary,
				title: theme.colors.success,
			} as const satisfies ToastColors;
		default:
			return {
				background: theme.colors.infoSurface,
				border: theme.colors.infoBorder,
				close: theme.colors.textSecondary,
				icon: theme.colors.info,
				iconBackground: theme.colors.infoMuted,
				message: theme.colors.textSecondary,
				title: theme.colors.info,
			} as const satisfies ToastColors;
	}
}

function getToastTitle(tone: ToastTone) {
	switch (tone) {
		case "error":
			return "Something went wrong.";
		case "success":
			return "Success.";
		default:
			return "Notice";
	}
}

function getToastIcon(tone: ToastTone): IconName {
	if (tone === "error") {
		return "alertTriangle";
	}

	return "checkCircle";
}

function createId() {
	return `${Date.now().toString(36)}:${Math.random().toString(36).slice(2, 10)}`;
}

const useStyles = createStyles((theme) => ({
	viewport: {
		position: "absolute",
		bottom: 0,
		left: 0,
		right: 0,
		zIndex: 100,
		paddingHorizontal: theme.spacing.lg,
		alignItems: "stretch",
	},
	toast: {
		alignSelf: "stretch",
		flexDirection: "row",
		alignItems: "center",
		gap: theme.spacing.md,
		borderWidth: 1,
		borderRadius: theme.radius.xl,
		paddingHorizontal: theme.spacing.md,
		paddingVertical: theme.spacing.md,
		...(theme.shadows.md as Omit<typeof theme.shadows.md, "elevation">),
		shadowOffset: { width: 0, height: 8 },
		shadowRadius: 20,
		elevation: 8,
	},
	toastIcon: {
		alignItems: "center",
		borderRadius: theme.radius.full,
		height: 28,
		justifyContent: "center",
		width: 28,
	},
}));
