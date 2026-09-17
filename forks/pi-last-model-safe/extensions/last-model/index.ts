import { homedir } from "node:os";
import { join } from "node:path";
import { SettingsManager, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { promoteModel } from "./promote.js";

function agentDir(): string {
	return process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
}

export default function (pi: ExtensionAPI) {
	pi.on("model_select", async (event, ctx) => {
		const settings = SettingsManager.create(ctx.cwd, agentDir());
		const modelReference = `${event.model.provider}/${event.model.id}`;

		settings.setDefaultModelAndProvider(event.model.provider, event.model.id);
		const enabledModels = promoteModel(settings.getEnabledModels(), modelReference);
		if (enabledModels) settings.setEnabledModels(enabledModels);
		await settings.flush();
	});
}
