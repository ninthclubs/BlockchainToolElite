import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, artifacts, network } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  // sanity: у контракта нет аргументов конструктора
  const art = await artifacts.readArtifact("FHEExpenseTracker");
  const ctor = (art.abi as any[]).find((x) => x.type === "constructor");
  log(
    `Constructor inputs: ${ctor?.inputs?.length ?? 0} ${
      ctor?.inputs ? JSON.stringify(ctor.inputs) : ""
    }`
  );

  // Деплой без args
  const deployment = await deploy("FHEExpenseTracker", {
    from: deployer,
    args: [],
    log: true,
    // waitConfirmations: network.live ? 2 : 0, // при желании — дождаться подтв.
  });
  log(`✅ FHEExpenseTracker deployed at: ${deployment.address}`);

  // Сидинга нет: суммы формируются только из зашифрованных транзакций пользователя.
  log("ℹ️ No seeding step (encrypted inputs must come via Relayer SDK at runtime).");
};

export default func;
func.id = "deploy_FHEExpenseTracker";
func.tags = ["FHEExpenseTracker"];
