// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/* Официальная библиотека Zama: только её используем */
import { FHE, euint64, externalEuint64 } from "@fhevm/solidity/lib/FHE.sol";
/* Конфиг сети: даёт адреса KMS/Oracle/ACL на Sepolia */
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

/**
 * @title FHEExpenseTracker
 * @notice Приватный трекер расходов.
 *         Пользователь отправляет зашифрованную трату (euint64, например центы),
 *         контракт накапливает её в его персональной зашифрованной сумме и
 *         возвращает зашифрованный итог.
 *
 * Важные детали:
 *  - Все вычисления над euint64 выполняются в транзакции (не в view/pure).
 *  - Контракту даём право переиспользовать шифротексты (FHE.allowThis).
 *  - Пользователю даём право расшифровки итога (FHE.allow(..., msg.sender)).
 *  - Геттеры возвращают bytes32-хэндлы — расшифровать сможет только тот,
 *    кому разрешено (или если сделано публичным через makeMyTotalPublic()).
 */
contract FHEExpenseTracker is SepoliaConfig {
    event ExpenseSubmitted(
        address indexed user,
        bytes32 amountHandle,
        bytes32 newTotalHandle
    );

    event TotalMadePublic(address indexed user, bytes32 totalHandle);
    event TotalShared(address indexed owner, address indexed viewer, bytes32 totalHandle);

    /* Персональные суммы расходов (зашифрованные) */
    mapping(address => euint64) private _sumByUser;
    mapping(address => bool)    private _hasSum;

    function version() external pure returns (string memory) {
        return "FHEExpenseTracker/1.0.0-sepolia";
    }

    /**
     * @notice Добавить зашифрованную трату и получить новый зашифрованный итог.
     * @param amountExt  внешний хэндл euint64 (из Relayer SDK)
     * @param proof      ZK-доказательство целостности (Relayer SDK формирует)
     * @return newTotal  euint64-хэндл новой общей суммы
     */
    function submitExpense(
        externalEuint64 amountExt,
        bytes calldata proof
    ) external returns (euint64 newTotal) {
        require(proof.length > 0, "Empty proof");

        // 1) Проверяем и десериализуем внешний хэндл
        euint64 amount = FHE.fromExternal(amountExt, proof);

        // 2) Текущая сумма пользователя или 0 при первом заходе
        euint64 current = _hasSum[msg.sender] ? _sumByUser[msg.sender] : FHE.asEuint64(0);

        // 3) Аккумуляция: sum += amount
        newTotal = FHE.add(current, amount);

        // 4) ACL:
        //    - контракту: чтобы использовать сумму в будущих транзакциях
        //    - пользователю: чтобы он мог делать userDecrypt(...)
        FHE.allowThis(newTotal);
        FHE.allow(newTotal, msg.sender);

        // 5) Сохраняем состояние
        _sumByUser[msg.sender] = newTotal;
        _hasSum[msg.sender] = true;

        emit ExpenseSubmitted(msg.sender, FHE.toBytes32(amount), FHE.toBytes32(newTotal));
        return newTotal;
    }

    /**
     * @notice Хэндл моей текущей суммы (для publicDecrypt/userDecrypt на фронте).
     *         Если расходов ещё не было — вернёт bytes32(0).
     */
    function getMyTotalHandle() external view returns (bytes32) {
        return _hasSum[msg.sender] ? FHE.toBytes32(_sumByUser[msg.sender]) : bytes32(0);
    }

    /**
     * @notice Хэндл суммы другого пользователя. Вернёт handle, но расшифровать
     *         его сможет только тот, кому это разрешено ACL (владелец, шарённый
     *         адрес или если сделано публичным).
     */
    function getTotalHandleOf(address user) external view returns (bytes32) {
        return _hasSum[user] ? FHE.toBytes32(_sumByUser[user]) : bytes32(0);
    }

    /**
     * @notice Сделать МОЮ текущую сумму публично дешифруемой всеми
     *         (например для табло/дашборда). Действие необратимо для данного handle.
     */
    function makeMyTotalPublic() external {
        require(_hasSum[msg.sender], "No total yet");
        euint64 total = _sumByUser[msg.sender];
        FHE.makePubliclyDecryptable(total);
        emit TotalMadePublic(msg.sender, FHE.toBytes32(total));
    }

    /**
     * @notice Поделиться доступом к МОЕЙ текущей сумме с конкретным адресом.
     *         Если позже сумма обновится (новый handle), доступ нужно будет выдать снова.
     */
    function shareMyTotal(address viewer) external {
        require(_hasSum[msg.sender], "No total yet");
        require(viewer != address(0), "Zero viewer");
        euint64 total = _sumByUser[msg.sender];

        // Разрешаем viewer дешифровать / использовать текущий handle
        FHE.allow(total, viewer);
        emit TotalShared(msg.sender, viewer, FHE.toBytes32(total));
    }
}
