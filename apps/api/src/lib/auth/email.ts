type ResetPasswordEmailData = {
	url: string;
	user: {
		email: string;
		name?: string | null;
	};
};

type VerificationEmailData = ResetPasswordEmailData & {
	token: string;
};

type ChangeEmailConfirmationData = VerificationEmailData & {
	newEmail: string;
};

type AttendeeReportNotificationData = {
	eventId: string;
	reason: string;
	reportId: string;
};

function escapeHtml(value: string) {
	return value.replace(/[&<>"']/g, (char) => {
		switch (char) {
			case "&":
				return "&amp;";
			case "<":
				return "&lt;";
			case ">":
				return "&gt;";
			case '"':
				return "&quot;";
			case "'":
				return "&#39;";
			default:
				return char;
		}
	});
}

export async function sendResetPasswordEmail(emailService: SendEmail, data: ResetPasswordEmailData) {
	const resetUrl = data.url;

	const name = data.user.name?.trim();
	const greeting = name ? `Hi ${name},` : "Hi,";

	const escapedGreeting = escapeHtml(greeting);
	const escapedResetUrl = escapeHtml(resetUrl);

	const html = `
		<p>${escapedGreeting}</p>
		<p>We received a request to reset your AReach password.</p>
		<p><a href="${escapedResetUrl}">Reset your password</a></p>
		<p>This link expires in 1 hour. If you did not request this, you can ignore this email.</p>
	`;
	const text = [
		greeting,
		"We received a request to reset your AReach password.",
		`Reset your password:\n${resetUrl}`,
		"This link expires in 1 hour. If you did not request this, you can ignore this email.",
	].join("\n\n");

	await emailService.send({
		from: { email: "no-reply@example.invalid", name: "AReach" },
		to: data.user.email,
		subject: "Reset your AReach password",
		html,
		text,
	});
}

export async function sendVerificationEmail(emailService: SendEmail, data: VerificationEmailData) {
	const verificationUrl = data.url;
	const name = data.user.name?.trim();
	const greeting = name ? `Hi ${name},` : "Hi,";

	const escapedGreeting = escapeHtml(greeting);
	const escapedVerificationUrl = escapeHtml(verificationUrl);

	const html = `
		<p>${escapedGreeting}</p>
		<p>Please verify your email address to finish setting up your AReach account.</p>
		<p><a href="${escapedVerificationUrl}">Verify your email address</a></p>
		<p>If you did not request this, you can ignore this email.</p>
	`;
	const text = [
		greeting,
		"Please verify your email address to finish setting up your AReach account.",
		`Verify your email address:
${verificationUrl}`,
		"If you did not request this, you can ignore this email.",
	].join("\n\n");

	await emailService.send({
		from: { email: "no-reply@example.invalid", name: "AReach" },
		to: data.user.email,
		subject: "Verify your AReach email",
		html,
		text,
	});
}

export async function sendChangeEmailConfirmationEmail(emailService: SendEmail, data: ChangeEmailConfirmationData) {
	const confirmationUrl = data.url;
	const name = data.user.name?.trim();
	const greeting = name ? `Hi ${name},` : "Hi,";

	const escapedGreeting = escapeHtml(greeting);
	const escapedNewEmail = escapeHtml(data.newEmail);
	const escapedConfirmationUrl = escapeHtml(confirmationUrl);

	const html = `
		<p>${escapedGreeting}</p>
		<p>We received a request to change your AReach email address to <strong>${escapedNewEmail}</strong>.</p>
		<p><a href="${escapedConfirmationUrl}">Confirm email change</a></p>
		<p>If you did not request this, you can ignore this email.</p>
	`;
	const text = [
		greeting,
		`We received a request to change your AReach email address to ${data.newEmail}.`,
		`Confirm email change:
${confirmationUrl}`,
		"If you did not request this, you can ignore this email.",
	].join("\n\n");

	await emailService.send({
		from: { email: "no-reply@example.invalid", name: "AReach" },
		to: data.user.email,
		subject: "Confirm your AReach email change",
		html,
		text,
	});
}

export async function sendAttendeeReportNotification(
	emailService: SendEmail,
	recipient: string | undefined,
	data: AttendeeReportNotificationData,
) {
	const to = recipient?.trim();

	if (!to) {
		return;
	}

	const escapedReportId = escapeHtml(data.reportId);
	const escapedEventId = escapeHtml(data.eventId);
	const escapedReason = escapeHtml(data.reason);

	await emailService.send({
		from: { email: "no-reply@example.invalid", name: "AReach" },
		to,
		subject: "New AReach attendee report",
		html: `
			<p>A new attendee report is waiting for review.</p>
			<p><strong>Report:</strong> ${escapedReportId}</p>
			<p><strong>Event:</strong> ${escapedEventId}</p>
			<p><strong>Reason:</strong> ${escapedReason}</p>
		`,
		text: [
			"A new attendee report is waiting for review.",
			`Report: ${data.reportId}`,
			`Event: ${data.eventId}`,
			`Reason: ${data.reason}`,
		].join("\n"),
	});
}
