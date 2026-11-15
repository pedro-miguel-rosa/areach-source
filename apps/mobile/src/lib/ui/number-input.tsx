import { TextInput, type TextInputProps } from "@/lib/ui/text-input";

export type NumberInputProps = Omit<TextInputProps, "keyboardType" | "onChange" | "secureTextEntry"> & {
	allowDecimal?: boolean;
	allowNegative?: boolean;
	onChange?: (value: string) => void;
	onChangeNumber?: (value: number | null) => void;
};

export function NumberInput(props: NumberInputProps) {
	const { allowDecimal = false, allowNegative = false, onChange, onChangeNumber, ...inputProps } = props;

	const handleChange = (value: string) => {
		const nextValue = normalizeNumberText(value, { allowDecimal, allowNegative });
		onChange?.(nextValue);
		onChangeNumber?.(toNumberValue(nextValue));
	};

	return <TextInput {...inputProps} keyboardType={allowDecimal ? "decimal-pad" : "number-pad"} onChange={handleChange} />;
}

function normalizeNumberText(value: string, options: { allowDecimal: boolean; allowNegative: boolean }) {
	const { allowDecimal, allowNegative } = options;
	const sign = allowNegative && value.trimStart().startsWith("-") ? "-" : "";
	let nextValue = value.replace(allowDecimal ? /[^\d.]/g : /\D+/g, "");

	if (allowDecimal) {
		const [integerPart = "", ...decimalParts] = nextValue.split(".");
		nextValue = decimalParts.length > 0 ? `${integerPart}.${decimalParts.join("")}` : integerPart;
	}

	return `${sign}${nextValue}`;
}

function toNumberValue(value: string) {
	if (!value || value === "-" || value === ".") {
		return null;
	}

	const nextValue = Number(value);

	return Number.isFinite(nextValue) ? nextValue : null;
}
