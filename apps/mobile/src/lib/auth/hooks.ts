import { useState } from "react";
import { waitForEventSyncs } from "@/features/events/sync";
import { stopAReachLiveEventActivities } from "@/features/presence/activity";
import { waitForProfileSyncs } from "@/features/profile/sync";
import { apiClient } from "@/lib/api/client";
import { clearLocalAccountData } from "@/lib/db/cleanup";
import { showToast } from "@/lib/ui/toast";
import AReachSpatial from "@/modules/areach-spatial";
import { authClient, clearStoredAuthSession } from "./client";

export type Error = {
	code: "invalidCredentials" | "invalidPassword" | "network" | "passwordTooLong" | "passwordTooShort" | "unknown" | "userAlreadyExists";
	message: string;
	title: string;
};

export type ChangeEmailError = {
	code: "emailAlreadyInUse" | "emailIsSame" | "network" | "unknown";
	message: string;
	title: string;
};

export type DeleteAccountError = {
	code: "credentialAccountNotFound" | "invalidPassword" | "network" | "sessionExpired" | "unknown";
	message: string;
	title: string;
};

export function useSession() {
	const { data, ...state } = authClient.useSession();

	return { ...state, session: data };
}

export function useSignIn() {
	const [isSubmitting, setIsSubmitting] = useState(false);
	const [error, setError] = useState<Error | null>(null);

	async function signIn(input: { email: string; password: string }) {
		setIsSubmitting(true);
		setError(null);

		try {
			const response = await authClient.signIn.email(input);

			if (response.error) {
				const errorCode = response.error.code;

				if (errorCode === "INVALID_EMAIL_OR_PASSWORD") {
					setError({
						code: "invalidCredentials",
						title: "Sign in failed",
						message: "Incorrect email or password.",
					});
					return false;
				}

				setError({
					code: "unknown",
					title: "We couldn't sign you in.",
					message: "Please check your details and try again.",
				});
				return false;
			}

			showToast({
				title: "Signed in successfully.",
				message: "Welcome back to AReach.",
				tone: "success",
				durationMs: 3500,
			});

			return true;
		} catch (submitError) {
			console.error(submitError);
			setError({
				code: "network",
				title: "Unable to connect",
				message: "Check your internet connection and try again.",
			});
			return false;
		} finally {
			setIsSubmitting(false);
		}
	}

	function clearError() {
		setError(null);
	}

	return {
		clearError,
		error,
		isSubmitting,
		signIn,
	};
}

export function useSignUp() {
	const [isSubmitting, setIsSubmitting] = useState(false);
	const [error, setError] = useState<Error | null>(null);

	async function signUp(input: { email: string; name: string; password: string }) {
		setIsSubmitting(true);
		setError(null);

		try {
			const response = await authClient.signUp.email(input);

			if (response.error) {
				const errorCode = response.error.code;

				if (errorCode === "USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL") {
					setError({
						code: "userAlreadyExists",
						title: "An account already exists with this email.",
						message: "An account already exists with this email.",
					});
					return false;
				}

				setError({
					code: "unknown",
					title: "We couldn't create your account.",
					message: "Please check your details and try again.",
				});
				return false;
			}

			showToast({
				title: "Account created successfully!",
				message: "Welcome to AReach.",
				tone: "success",
				durationMs: 3500,
			});

			return true;
		} catch (submitError) {
			console.error(submitError);
			setError({
				code: "network",
				title: "Unable to connect",
				message: "Check your internet connection and try again.",
			});
			return false;
		} finally {
			setIsSubmitting(false);
		}
	}

	function clearError() {
		setError(null);
	}

	return {
		error,
		clearError,
		isSubmitting,
		signUp,
	};
}

export function useRequestPasswordReset() {
	const [isSubmitting, setIsSubmitting] = useState(false);
	const [error, setError] = useState<Error | null>(null);

	async function requestPasswordReset(input: { email: string }) {
		setIsSubmitting(true);
		setError(null);

		try {
			const response = await authClient.requestPasswordReset({
				email: input.email,
				// Better Auth requires a redirect target for generated reset links. The approved flow covers
				// requesting the email; token-based password replacement can be added when that UI is approved.
				redirectTo: "areach://reset-password",
			});

			if (response.error) {
				setError({
					code: "unknown",
					title: "We couldn't send the email.",
					message: "Please try again.",
				});
				return false;
			}

			showToast({
				title: "Password reset email sent.",
				message: "Check your inbox to continue.",
				tone: "success",
				durationMs: 3500,
			});

			return true;
		} catch (submitError) {
			console.error(submitError);
			setError({
				code: "network",
				title: "Unable to connect",
				message: "Check your internet connection and try again.",
			});
			return false;
		} finally {
			setIsSubmitting(false);
		}
	}

	function clearError() {
		setError(null);
	}

	return {
		error,
		clearError,
		isSubmitting,
		requestPasswordReset,
	};
}

export function useChangePassword() {
	const [isSubmitting, setIsSubmitting] = useState(false);
	const [error, setError] = useState<Error | null>(null);

	async function changePassword(input: { currentPassword: string; newPassword: string }) {
		setIsSubmitting(true);
		setError(null);

		try {
			const response = await authClient.changePassword(input);

			if (response.error) {
				switch (response.error.code) {
					case "INVALID_PASSWORD":
						setError({
							code: "invalidPassword",
							title: "Current password is incorrect",
							message: "Enter your current password and try again.",
						});
						break;
					case "PASSWORD_TOO_LONG":
						setError({
							code: "passwordTooLong",
							title: "New password is too long",
							message: "Choose a shorter password and try again.",
						});
						break;
					case "PASSWORD_TOO_SHORT":
						setError({
							code: "passwordTooShort",
							title: "New password is too short",
							message: "Your new password must contain at least 8 characters.",
						});
						break;
					default:
						setError({
							code: "unknown",
							title: "We couldn't change your password.",
							message: "Please check your details and try again.",
						});
				}

				return false;
			}

			showToast({
				title: "Password changed successfully.",
				message: "Your new password is now active.",
				tone: "success",
				durationMs: 3500,
			});

			return true;
		} catch (submitError) {
			console.error(submitError);
			setError({
				code: "network",
				title: "Unable to connect",
				message: "Check your internet connection and try again.",
			});
			return false;
		} finally {
			setIsSubmitting(false);
		}
	}

	function clearError() {
		setError(null);
	}

	return {
		changePassword,
		clearError,
		error,
		isSubmitting,
	};
}

export function useChangeEmail() {
	const [isSubmitting, setIsSubmitting] = useState(false);
	const [error, setError] = useState<ChangeEmailError | null>(null);

	async function changeEmail(newEmail: string) {
		setIsSubmitting(true);
		setError(null);

		try {
			const response = await apiClient.POST("/auth/change-email", {
				body: {
					callbackURL: "areach://profile",
					newEmail,
				},
			});

			if (response.error) {
				const responseMessage = "message" in response.error && typeof response.error.message === "string" ? response.error.message : "";
				const normalizedMessage = responseMessage.toLocaleLowerCase();

				if (normalizedMessage === "email is the same") {
					setError({
						code: "emailIsSame",
						title: "This is already your email",
						message: "Enter a different email address.",
					});
				} else if (normalizedMessage.includes("already") || normalizedMessage.includes("exists")) {
					setError({
						code: "emailAlreadyInUse",
						title: "That email is already in use",
						message: "Choose another email address and try again.",
					});
				} else {
					setError({
						code: "unknown",
						title: "We couldn't change your email.",
						message: responseMessage || "Please check your details and try again.",
					});
				}

				return false;
			}

			if (!response.data?.status) {
				setError({
					code: "unknown",
					title: "We couldn't change your email.",
					message: "Please try again.",
				});
				return false;
			}

			showToast({
				title: "Check your email.",
				message: "Follow the confirmation link to finish changing your email address.",
				tone: "success",
				durationMs: 5000,
			});

			return true;
		} catch (submitError) {
			console.error(submitError);
			setError({
				code: "network",
				title: "Unable to connect",
				message: "Check your internet connection and try again.",
			});
			return false;
		} finally {
			setIsSubmitting(false);
		}
	}

	function clearError() {
		setError(null);
	}

	return {
		changeEmail,
		clearError,
		error,
		isSubmitting,
	};
}

export function useSignOut() {
	async function signOut() {
		try {
			await authClient.signOut();
		} catch (error) {
			console.error(error);
			showToast({
				title: "Something went wrong.",
				message: "We couldn't sign you out right now.",
				tone: "error",
				durationMs: 5000,
			});
		}
	}

	return { signOut };
}

export function useDeleteAccount() {
	const [isSubmitting, setIsSubmitting] = useState(false);
	const [error, setError] = useState<DeleteAccountError | null>(null);

	async function deleteAccount(password: string) {
		setIsSubmitting(true);
		setError(null);

		try {
			const response = await authClient.deleteUser({ password });

			if (response.error) {
				switch (response.error.code) {
					case "INVALID_PASSWORD":
						setError({
							code: "invalidPassword",
							title: "Password is incorrect",
							message: "Enter your current password and try again.",
						});
						break;
					case "CREDENTIAL_ACCOUNT_NOT_FOUND":
						setError({
							code: "credentialAccountNotFound",
							title: "Password confirmation unavailable",
							message: "This account does not have a password that can be confirmed here.",
						});
						break;
					case "SESSION_EXPIRED":
						setError({
							code: "sessionExpired",
							title: "Your session has expired",
							message: "Sign in again before deleting your account.",
						});
						break;
					default:
						setError({
							code: "unknown",
							title: "We couldn't delete your account",
							message: "Please try again.",
						});
				}

				return false;
			}

			if (!response.data?.success) {
				setError({
					code: "unknown",
					title: "We couldn't delete your account",
					message: "Please try again.",
				});
				return false;
			}

			let cleanupError: unknown;
			try {
				await Promise.all([
					AReachSpatial.stopNearbyDiscovery().catch(() => undefined),
					stopAReachLiveEventActivities().catch(() => undefined),
				]);
				await waitForEventSyncs();
				await waitForProfileSyncs();
				await clearLocalAccountData();
			} catch (error) {
				cleanupError = error;
			}

			await clearStoredAuthSession();

			if (cleanupError) {
				console.error(cleanupError);
				showToast({
					message:
						"Your account was deleted, but some device data could not be cleared. Please reinstall AReach before sharing this device.",
					tone: "error",
					durationMs: 7000,
				});
			} else {
				showToast({
					title: "Account deleted.",
					message: "Your AReach account and device data have been removed.",
					tone: "success",
					durationMs: 5000,
				});
			}

			return true;
		} catch {
			console.error("Account deletion request failed");
			setError({
				code: "network",
				title: "Unable to connect",
				message: "Check your internet connection and try again.",
			});
			return false;
		} finally {
			setIsSubmitting(false);
		}
	}

	function clearError() {
		setError(null);
	}

	return {
		clearError,
		deleteAccount,
		error,
		isSubmitting,
	};
}
