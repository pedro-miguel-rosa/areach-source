import { useEffect, useMemo, useRef, useState } from "react";
import { MAX_ASK_ME_ABOUT_TOPIC_LENGTH, MAX_ASK_ME_ABOUT_TOPICS } from "@/features/profile/constants";
import { useProfile } from "@/features/profile/hooks";
import { useSession } from "@/lib/auth/hooks";
import { router } from "@/lib/navigation/router";
import { useTheme } from "@/lib/theme/hooks";
import { Button } from "@/lib/ui/button";
import { Card } from "@/lib/ui/card";
import { Column } from "@/lib/ui/column";
import { IconButton } from "@/lib/ui/icon-button";
import { Row } from "@/lib/ui/row";
import { Screen } from "@/lib/ui/screen";
import { Text } from "@/lib/ui/text";
import { TextInput } from "@/lib/ui/text-input";

type ProfileForm = {
	name: string;
	headline: string;
	askMeAbout: string[];
	topicDraft: string;
};

export default function EditProfileScreen() {
	const theme = useTheme();
	const { session } = useSession();
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

	const { isSubmitting, profile, submitProfile } = useProfile(userId, profileSeed);
	const [form, setForm] = useState<ProfileForm>(() => ({
		name: sessionUserName,
		headline: "",
		askMeAbout: [],
		topicDraft: "",
	}));
	const [askMeAboutError, setAskMeAboutError] = useState<string>();
	const hasHydratedForm = useRef(false);
	const hasReachedTopicLimit = form.askMeAbout.length >= MAX_ASK_ME_ABOUT_TOPICS;

	useEffect(() => {
		if (!profile || hasHydratedForm.current) {
			return;
		}

		hasHydratedForm.current = true;
		setForm({
			name: profile.name,
			headline: profile.headline,
			askMeAbout: profile.askMeAbout,
			topicDraft: "",
		});
	}, [profile]);

	const addTopic = () => {
		const topic = form.topicDraft.trim();

		if (!topic) {
			setAskMeAboutError("Enter a topic before adding it.");
			return;
		}

		if (topic.length > MAX_ASK_ME_ABOUT_TOPIC_LENGTH) {
			setAskMeAboutError(`Topics must be ${MAX_ASK_ME_ABOUT_TOPIC_LENGTH} characters or fewer.`);
			return;
		}

		if (form.askMeAbout.some((value) => value.toLocaleLowerCase() === topic.toLocaleLowerCase())) {
			setAskMeAboutError("That topic is already added.");
			return;
		}

		if (form.askMeAbout.length >= MAX_ASK_ME_ABOUT_TOPICS) {
			setAskMeAboutError(`You can add up to ${MAX_ASK_ME_ABOUT_TOPICS} topics.`);
			return;
		}

		setForm((current) => ({
			...current,
			askMeAbout: [...current.askMeAbout, topic],
			topicDraft: "",
		}));
		setAskMeAboutError(undefined);
	};

	const removeTopic = (topicToRemove: string) => {
		setForm((current) => ({
			...current,
			askMeAbout: current.askMeAbout.filter((topic) => topic !== topicToRemove),
		}));
		setAskMeAboutError(undefined);
	};

	const handleTopicDraftChange = (topicDraft: string) => {
		setForm((current) => ({ ...current, topicDraft }));
		if (askMeAboutError) {
			setAskMeAboutError(undefined);
		}
	};

	const handleSubmit = async () => {
		let topics: string[];

		try {
			const values = form.topicDraft.trim() ? [...form.askMeAbout, form.topicDraft] : form.askMeAbout;
			const normalizedTopics: string[] = [];
			const seen = new Set<string>();

			for (const value of values) {
				const topic = value.trim();

				if (!topic) {
					continue;
				}

				if (topic.length > MAX_ASK_ME_ABOUT_TOPIC_LENGTH) {
					throw new Error(`Each topic must be ${MAX_ASK_ME_ABOUT_TOPIC_LENGTH} characters or fewer.`);
				}

				const key = topic.toLocaleLowerCase();

				if (seen.has(key)) {
					continue;
				}

				seen.add(key);
				normalizedTopics.push(topic);
			}

			if (normalizedTopics.length > MAX_ASK_ME_ABOUT_TOPICS) {
				throw new Error(`Add up to ${MAX_ASK_ME_ABOUT_TOPICS} topics.`);
			}

			topics = normalizedTopics;
		} catch (error) {
			setAskMeAboutError(error instanceof Error ? error.message : "Check your conversation topics.");
			return;
		}

		const nextProfile = await submitProfile({
			name: form.name,
			headline: form.headline,
			askMeAbout: topics,
		});

		if (!nextProfile) {
			return;
		}

		router.back();
	};

	return (
		<Screen headerInset scrollable>
			<Column gap="lg" paddingHorizontal="lg" paddingVertical="lg">
				<Card>
					<Column gap="md">
						<Text size="sm" weight="bold">
							Update your profile details.
						</Text>
						<TextInput label="Name" onChange={(name) => setForm((current) => ({ ...current, name }))} value={form.name} />
						<TextInput label="Headline" onChange={(headline) => setForm((current) => ({ ...current, headline }))} value={form.headline} />

						<Column gap="sm">
							<Column gap="xxs">
								<Text size="sm" weight="bold">
									Ask me about…
								</Text>
								<Text color={theme.colors.textSecondary} size="sm">
									Choose up to {MAX_ASK_ME_ABOUT_TOPICS} topics to help other attendees start conversations.
								</Text>
							</Column>

							{form.askMeAbout.length > 0 ? (
								<Column gap="xs">
									{form.askMeAbout.map((topic) => (
										<Row
											align="center"
											backgroundColor={theme.colors.surfaceMuted}
											borderColor={theme.colors.border}
											borderRadius={theme.radius.md}
											borderWidth={1}
											gap="sm"
											key={topic}
											minHeight={48}
											paddingLeft="md"
											paddingRight="xs"
										>
											<Column flex minWidth={0}>
												<Text numberOfLines={1}>{topic}</Text>
											</Column>
											<IconButton accessibilityLabel={`Remove ${topic}`} icon="xMark" iconSize={16} onPress={() => removeTopic(topic)} />
										</Row>
									))}
								</Column>
							) : null}

							<Column gap="xs">
								<Text size="sm" weight="semibold">
									Add a topic
								</Text>
								<Row align="flex-start" gap="sm">
									<Column flex>
										<TextInput
											autoCapitalize="sentences"
											autoCorrect
											editable={!hasReachedTopicLimit}
											error={askMeAboutError}
											maxLength={MAX_ASK_ME_ABOUT_TOPIC_LENGTH}
											onChange={handleTopicDraftChange}
											onSubmitEditing={addTopic}
											placeholder={hasReachedTopicLimit ? "Maximum reached" : "e.g. Web Development"}
											returnKeyType="done"
											value={form.topicDraft}
										/>
									</Column>
									<Button disabled={hasReachedTopicLimit} onPress={addTopic} size="sm" variant="surface">
										Add
									</Button>
								</Row>
							</Column>
						</Column>

						<Row gap="sm">
							<Button disabled={isSubmitting} flex onPress={router.back} variant="outline">
								Cancel
							</Button>
							<Button disabled={isSubmitting} flex loading={isSubmitting} onPress={handleSubmit}>
								Save
							</Button>
						</Row>
					</Column>
				</Card>
			</Column>
		</Screen>
	);
}
