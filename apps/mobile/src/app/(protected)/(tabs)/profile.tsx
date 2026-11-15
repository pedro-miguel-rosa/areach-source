import { useMemo } from "react";
import { Pressable } from "react-native";
import { useEvents } from "@/features/events/hooks";
import { useProfile } from "@/features/profile/hooks";
import { useSession, useSignOut } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { Icon } from "@/lib/ui/icon";
import { MenuList, type MenuListItem } from "@/lib/ui/menu-list";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

export default function ProfileScreen() {
	const { session } = useSession();
	const { signOut } = useSignOut();
	const theme = useTheme();
	const userId = session?.user.id ?? "";
	const sessionUser = session?.user;
	const sessionUserEmail = sessionUser?.email ?? "";
	const sessionUserName = sessionUser?.name || sessionUserEmail || "Unknown user";
	const hasSessionUser = Boolean(sessionUser);

	const profileSeed = useMemo(
		() =>
			hasSessionUser
				? {
						name: sessionUserName,
						email: sessionUserEmail,
					}
				: undefined,
		[hasSessionUser, sessionUserEmail, sessionUserName],
	);

	const { data: events } = useEvents(userId);
	const { profile } = useProfile(userId, profileSeed);

	const userLabel = profile?.name || session?.user.name || session?.user.email || "Unknown user";
	const hostedCount = events.filter((event) => event.createdByUser).length;
	const joinedCount = events.filter((event) => !event.createdByUser).length;
	const accountOptions: MenuListItem[] = [
		{
			icon: "user",
			label: "Edit Profile",
			onPress: () => router.push("/profile/edit" as never),
		},
		{
			icon: "lock",
			label: "Change Password",
			onPress: () => router.push("/profile/change-password" as never),
		},
		{
			icon: "mail",
			label: "Change Email",
			onPress: () => router.push("/profile/change-email" as never),
		},
		{
			destructive: true,
			icon: "delete",
			label: "Delete Account",
			onPress: () => router.push("/profile/delete-account" as never),
		},
	];

	const preferenceOptions: MenuListItem[] = [
		{
			icon: "appearance",
			label: "Appearance",
			onPress: () => router.push("/profile/appearance" as never),
		},
		{
			icon: "nosign",
			label: "Privacy",
			onPress: () => router.push("/profile/privacy" as never),
		},
		{
			icon: "users",
			label: "Blocked Users",
			onPress: () => router.push("/profile/blocked" as never),
		},
	];

	const supportOptions: MenuListItem[] = [
		{
			icon: "help",
			label: "Help & Support",
			onPress: () => router.push("/profile/help-support" as never),
		},
		{
			icon: "info",
			label: "About AReach",
			onPress: () => router.push("/profile/about" as never),
		},
	];

	return (
		<Screen scrollable>
			<Column gap="lg" paddingHorizontal="lg" paddingVertical="lg">
				<Card padding="lg">
					<Column gap="sm">
						<Text numberOfLines={1} size="xl" weight="bold">
							{userLabel}
						</Text>
						{profile?.headline ? (
							<Text color={theme.colors.textSecondary} numberOfLines={2}>
								{profile.headline}
							</Text>
						) : null}

						<Column gap="xs" marginTop="sm">
							<Text size="sm" weight="bold">
								Ask me about…
							</Text>
							{profile?.askMeAbout.length ? (
								<Column gap="xxs">
									{profile.askMeAbout.map((topic) => (
										<Row align="center" gap="sm" key={topic}>
											<Icon color={theme.colors.success} name="circleFilled" size={8} />
											<Text color={theme.colors.textSecondary} size="sm">
												{topic}
											</Text>
										</Row>
									))}
								</Column>
							) : (
								<Text color={theme.colors.textSecondary} size="sm">
									Add a few topics to help other attendees start conversations.
								</Text>
							)}
						</Column>
					</Column>
				</Card>

				<Card padding="sm">
					<Row align="center" justify="space-between">
						<Column align="center" flex gap="xxs">
							<Text align="center" size="md" weight="bold">
								{joinedCount}
							</Text>
							<Text align="center" color={theme.colors.textSecondary} size="xs">
								Events joined
							</Text>
						</Column>
						<Column align="center" flex gap="xxs">
							<Text align="center" size="md" weight="bold">
								{hostedCount}
							</Text>
							<Text align="center" color={theme.colors.textSecondary} size="xs">
								Events hosted
							</Text>
						</Column>
					</Row>
				</Card>

				<Column gap="xs">
					<Text size="sm" weight="bold">
						Account
					</Text>
					<MenuList items={accountOptions} />
				</Column>

				<Column gap="xs">
					<Text size="sm" weight="bold">
						Preferences
					</Text>
					<MenuList items={preferenceOptions} />
				</Column>

				<Column gap="xs">
					<Text size="sm" weight="bold">
						Support
					</Text>
					<MenuList items={supportOptions} />
				</Column>

				<Pressable
					accessibilityRole="button"
					onPress={() => void signOut()}
					style={{ alignSelf: "flex-start", justifyContent: "center", minHeight: 44 }}
				>
					<Row align="center" gap="sm">
						<Icon color={theme.colors.error} name="logOut" size={18} />
						<Text color={theme.colors.error} size="sm" weight="semibold">
							Log out
						</Text>
					</Row>
				</Pressable>
			</Column>
		</Screen>
	);
}
