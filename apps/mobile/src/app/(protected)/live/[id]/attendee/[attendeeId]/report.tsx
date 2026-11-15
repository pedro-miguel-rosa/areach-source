import { useState } from "react";
import { Pressable } from "react-native";
import { useLiveEvent } from "@/features/events/context";
import { reportEventAttendee } from "@/features/privacy/actions";
import { ATTENDEE_REPORT_REASONS, type AttendeeReportReason } from "@/features/privacy/types";
import { useSession } from "@/lib/auth/hooks";
import { router, usePathParam } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { ErrorCard } from "@/lib/ui/error-card";
import { Icon } from "@/lib/ui/icon";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";
import { showToast } from "@/lib/ui/toast";

const REASON_LABELS: Record<AttendeeReportReason, string> = {
	harassment_or_abusive_behavior: "Harassment or abusive behavior",
	impersonation: "Impersonation",
	inappropriate_profile_content: "Inappropriate profile content",
	other: "Other",
	spam: "Spam",
};

export default function ReportAttendeeScreen() {
	const theme = useTheme();
	const { session } = useSession();
	const { event } = useLiveEvent();
	const attendeeId = usePathParam("attendeeId");
	const [reason, setReason] = useState<AttendeeReportReason>();
	const [isSubmitting, setIsSubmitting] = useState(false);
	const [error, setError] = useState<string>();

	const submit = async () => {
		if (!reason || !session?.user.id || isSubmitting) {
			return;
		}

		setIsSubmitting(true);
		setError(undefined);
		try {
			const result = await reportEventAttendee(event.remoteId, attendeeId, reason);

			if (result.created) {
				showToast({ message: "Report submitted. Thank you for helping keep AReach safe.", tone: "success", durationMs: 5000 });
			} else {
				showToast({ message: "You already reported this attendee for this event.", tone: "info", durationMs: 5000 });
			}

			router.back();
		} catch (submitError) {
			setError(submitError instanceof Error ? submitError.message : "Unable to submit this report.");
		} finally {
			setIsSubmitting(false);
		}
	};

	return (
		<Screen headerInset scrollable>
			<Column gap="lg" paddingBottom="xl" paddingHorizontal="lg" paddingTop="lg">
				<Column gap="xs">
					<Text size="lg" weight="bold">
						Why are you reporting this attendee?
					</Text>
					<Text color={theme.colors.textSecondary} size="sm">
						Choose the reason that best describes the issue. Reports are reviewed by the AReach team.
					</Text>
				</Column>

				<Card padding="sm">
					{ATTENDEE_REPORT_REASONS.map((item, index) => {
						const isSelected = item === reason;

						return (
							<Pressable
								accessibilityLabel={REASON_LABELS[item]}
								accessibilityRole="radio"
								accessibilityState={{ selected: isSelected }}
								key={item}
								onPress={() => setReason(item)}
								style={{
									borderBottomColor: theme.colors.border,
									borderBottomWidth: index < ATTENDEE_REPORT_REASONS.length - 1 ? 1 : 0,
									minHeight: 52,
									paddingHorizontal: theme.spacing.md,
									paddingVertical: theme.spacing.sm,
								}}
							>
								<Row align="center" gap="md" justify="space-between">
									<Column flex>
										<Text size="sm">{REASON_LABELS[item]}</Text>
									</Column>
									<Icon color={theme.colors.textLink} name="checkCircle" size={22} style={{ opacity: isSelected ? 1 : 0 }} />
								</Row>
							</Pressable>
						);
					})}
				</Card>

				{error ? <ErrorCard message={error} title="Report could not be submitted" /> : null}

				<Button disabled={!reason || isSubmitting} loading={isSubmitting} onPress={() => void submit()}>
					Submit Report
				</Button>
			</Column>
		</Screen>
	);
}
