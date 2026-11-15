import { useCallback, useEffect, useRef, useState } from "react";
import { RefreshControl } from "react-native";
import { unblockUser } from "@/features/privacy/actions";
import { useBlockedUsers } from "@/features/privacy/hooks";
import { syncPrivacy } from "@/features/privacy/sync";
import { useSession } from "@/lib/auth/hooks";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { ErrorCard } from "@/lib/ui/error-card";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Skeleton } from "@/lib/ui/skeleton";
import { Text } from "@/lib/ui/text";
import { showToast } from "@/lib/ui/toast";

export default function BlockedUsersScreen() {
	const theme = useTheme();
	const { session } = useSession();
	const viewerId = session?.user.id ?? "";
	const { data: blockedUsers, error, isPending } = useBlockedUsers(viewerId);
	const [isRefreshing, setIsRefreshing] = useState(false);
	const [unblockingUserId, setUnblockingUserId] = useState<string>();
	const isRefreshingRef = useRef(false);

	const refresh = useCallback(async () => {
		if (!viewerId || isRefreshingRef.current) {
			return;
		}

		isRefreshingRef.current = true;
		setIsRefreshing(true);
		try {
			await syncPrivacy(viewerId);
		} catch (refreshError) {
			showToast({
				error: refreshError,
				message: refreshError instanceof Error ? refreshError.message : "Unable to refresh blocked users.",
				tone: "error",
				durationMs: 5000,
			});
		} finally {
			isRefreshingRef.current = false;
			setIsRefreshing(false);
		}
	}, [viewerId]);

	useEffect(() => {
		void refresh();
	}, [refresh]);

	const handleUnblock = async (userId: string) => {
		if (!viewerId || unblockingUserId) {
			return;
		}

		setUnblockingUserId(userId);
		try {
			await unblockUser(viewerId, userId);
			showToast({ message: "User unblocked.", tone: "success" });
		} catch (unblockError) {
			showToast({
				error: unblockError,
				message: unblockError instanceof Error ? unblockError.message : "Unable to unblock this user.",
				tone: "error",
				durationMs: 5000,
			});
		} finally {
			setUnblockingUserId(undefined);
		}
	};

	return (
		<Screen
			headerInset
			refreshControl={
				<RefreshControl
					colors={[theme.colors.textLink]}
					onRefresh={() => void refresh()}
					progressBackgroundColor={theme.colors.surfaceRaised}
					refreshing={isRefreshing}
					tintColor={theme.colors.textLink}
				/>
			}
			scrollable
		>
			<Column gap="lg" paddingBottom="xl" paddingHorizontal="lg" paddingTop="lg">
				<Column gap="xs">
					<Text size="lg" weight="bold">
						Blocked users
					</Text>
					<Text color={theme.colors.textSecondary} size="sm">
						Blocked users cannot discover you, and you will not see each other in event attendee or nearby results.
					</Text>
				</Column>

				{error ? <ErrorCard message={error.message} title="Unable to load blocked users" /> : null}

				{isPending ? (
					<Column gap="xs">
						{["first", "second"].map((key) => (
							<Card key={key} padding="md">
								<Row align="center" gap="md">
									<Column flex gap="xxs">
										<Skeleton height={18} width="45%" />
										<Skeleton height={14} width="28%" />
									</Column>
									<Skeleton height={44} width={96} />
								</Row>
							</Card>
						))}
					</Column>
				) : blockedUsers.length === 0 ? (
					<Card>
						<Column gap="sm">
							<Text size="lg" weight="bold">
								No blocked users
							</Text>
							<Text color={theme.colors.textSecondary}>You can block an attendee from their profile during a live event.</Text>
						</Column>
					</Card>
				) : (
					<Column gap="xs">
						{blockedUsers.map((blockedUser) => (
							<Card key={blockedUser.userId} padding="md">
								<Row align="center" gap="md" justify="space-between">
									<Column flex gap="xxs" minWidth={0}>
										<Text numberOfLines={1} weight="semibold">
											{blockedUser.name}
										</Text>
										<Text color={theme.colors.textSecondary} size="sm">
											Hidden from your attendee discovery
										</Text>
									</Column>
									<Button
										disabled={Boolean(unblockingUserId)}
										loading={unblockingUserId === blockedUser.userId}
										onPress={() => void handleUnblock(blockedUser.userId)}
										size="sm"
										variant="surface"
									>
										Unblock
									</Button>
								</Row>
							</Card>
						))}
					</Column>
				)}
			</Column>
		</Screen>
	);
}
