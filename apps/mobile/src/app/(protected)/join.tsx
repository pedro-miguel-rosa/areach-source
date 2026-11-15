import { useState } from "react";
import { useJoinEvent } from "@/features/events/hooks";
import { useSession } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { CodeInput } from "@/lib/ui/code-input";
import { Column } from "@/lib/ui/column";
import { IconIllustration } from "@/lib/ui/icon-illustration";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";

export default function JoinScreen() {
	const { colors } = useTheme();
	const { session } = useSession();
	const { isSubmitting, joinEvent } = useJoinEvent();

	const [inviteCode, setInviteCode] = useState("");

	const viewerId = session?.user.id ?? "";
	const hasJoinInput = inviteCode.trim().length > 0;
	const isJoinDisabled = !viewerId || !hasJoinInput || isSubmitting;

	const handleJoinEvent = async () => {
		if (isJoinDisabled) {
			return;
		}

		const submissionInviteCode = inviteCode.trim().toUpperCase();
		const wasQueued = await joinEvent({ viewerId, inviteCode: submissionInviteCode });

		if (wasQueued) {
			setInviteCode("");
			router.replace("/events" as never);
			return;
		}
	};

	const handleInviteCodeChange = (nextValue: string) => {
		const normalized = nextValue
			.toUpperCase()
			.replace(/[^A-Z0-9]/g, "")
			.slice(0, 6);

		setInviteCode(normalized);
	};

	return (
		<Screen fill scrollable>
			<Column flex gap="xl" justify="center" paddingBottom="xl" paddingHorizontal="xl" width="100%">
				<IconIllustration icon="ticket" />

				<Column align="center" gap="xs">
					<Text align="center" color={colors.text} size="md" weight="bold">
						Enter the event code
					</Text>
					<Text align="center" color={colors.textSecondary} size="sm">
						shared by the host to join.
					</Text>
				</Column>

				<CodeInput length={6} onChange={handleInviteCodeChange} value={inviteCode} />

				<Button disabled={isJoinDisabled} loading={isSubmitting} onPress={handleJoinEvent}>
					Join Event
				</Button>
			</Column>
		</Screen>
	);
}
