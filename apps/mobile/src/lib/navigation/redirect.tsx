import { Redirect as ExpoRedirect } from "expo-router";
import type { ComponentProps } from "react";

type RedirectProps = ComponentProps<typeof ExpoRedirect>;

export function Redirect(props: RedirectProps) {
	return <ExpoRedirect {...props} />;
}
