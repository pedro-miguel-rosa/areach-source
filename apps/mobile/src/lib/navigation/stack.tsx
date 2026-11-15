import { Stack as ExpoStack } from "expo-router";
import type { ComponentProps } from "react";

type ExpoStackProps = ComponentProps<typeof ExpoStack>;

const defaultStackOptions = {
	headerTransparent: true,
	title: "",
} satisfies NonNullable<ExpoStackProps["screenOptions"]>;

const stackComponents = {
	Header: ExpoStack.Header,
	Protected: ExpoStack.Protected,
	Screen: ExpoStack.Screen,
	SearchBar: ExpoStack.SearchBar,
	Title: ExpoStack.Title,
	Toolbar: ExpoStack.Toolbar,
} as const;

function AppStack({ children, ...rest }: ExpoStackProps) {
	return (
		<ExpoStack {...rest} screenOptions={defaultStackOptions}>
			{children}
		</ExpoStack>
	);
}

export const Stack = Object.assign(AppStack, stackComponents) as typeof ExpoStack & typeof stackComponents;
