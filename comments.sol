//SPDX-License-1dentifier: LGPL-3.0-on1Y
//SPDX-License-Identifier: MIT
/*
    =============================================================
                        PROJECT: SecureUpgradeableVault
    =============================================================

    Objetivo:
    Diseñar un Vault multiusuario enfocado en seguridad,
    buenas prácticas de arquitectura y posible upgradeabilidad.

    Este contrato NO es un ejercicio básico de deposit/withdraw.
    Debe cumplir estándares profesionales de Smart Contract Engineering.


    -------------------------------------------------------------
    CORE REQUIREMENTS (MVP PROFESIONAL)
    -------------------------------------------------------------

    [1] Multi-user accounting
        - mapping(address => uint256) private balances; ✔
        - Cada usuario solo puede retirar su propio balance. ✔
        - No debe existir forma de manipular balances ajenos. ✔

    [2] Deposit
        - Solo se permite depositar Ether (msg.value > 0). ✔
        - Debe emitir evento Deposit(address indexed user, uint256 amount).✔
        - Debe actualizar estado antes de cualquier interacción externa.✔

    [3] Withdraw
        - Patrón Checks-Effects-Interactions. ✔
        - Protección contra reentrancy (ReentrancyGuard). ✔
        - Validar balance suficiente.✔
        - Emitir evento Withdraw(address indexed user, uint256 amount).✔

    [4] Access Control ✔
        - Ownable o AccessControl.
        - Solo el owner puede:
            - Pausar el contrato.
            - Activar funciones administrativas.
        - Considerar rol ADMIN_ROLE si usas AccessControl.

    [5] Pausable ✔
        - Permitir pausar depósitos y retiros en caso de emergencia.
        - Usar whenNotPaused modifier.

    [6] Custom Errors
        - error InsufficientBalance(); ✔
        - error ZeroDeposit();✔
        - error TransferFailed();✔
        - error NotAuthorized();✔

        (Reducen gas comparado con require strings)

    [7] Eventos
        - event Deposit(address indexed user, uint256 amount);✔
        - event Withdraw(address indexed user, uint256 amount);✔
        - event EmergencyPause(address indexed triggeredBy);✔

    -------------------------------------------------------------
    ADVANCED FEATURES (Nivel Empresa)
    -------------------------------------------------------------

    [8] Reentrancy Protection
        - Usar OpenZeppelin ReentrancyGuard
        - Aplicar nonReentrant en withdraw()

    [9] Gas Optimization
        - Usar custom errors.
        - Minimizar writes innecesarios en storage.
        - Marcar variables como immutable cuando aplique.

    [10] Storage Layout Awareness
        - Mantener orden de variables consistente.
        - Si el contrato será upgradeable:
            - NO cambiar el orden de variables.
            - Reservar storage gaps:
                uint256[50] private __gap;

    [11] Upgradeability (Opcional pero recomendado)
        - Implementar patrón UUPS o Transparent Proxy.
        - Separar lógica de almacenamiento.
        - Reemplazar constructor por initialize().

    [12] Emergency Withdraw (Solo Owner)
        - Permitir rescatar fondos en caso crítico.
        - Debe ser extremadamente controlado.
        - Emitir evento.

    -------------------------------------------------------------
    SECURITY PRINCIPLES
    -------------------------------------------------------------

    - Nunca usar tx.origin para autorización.
    - Nunca hacer transfer antes de actualizar estado.
    - No confiar en inputs externos.
    - No usar call sin verificar resultado.
    - Considerar reentrancy cross-function.
    - Pensar en ataques de DOS por gas.

    -------------------------------------------------------------
    TESTING REQUIREMENTS
    -------------------------------------------------------------

    - Test deposit correcto.
    - Test withdraw correcto.
    - Test reentrancy attack simulation.
    - Test pause functionality.
    - Test access control restrictions.
    - Test edge cases (withdraw 0, deposit 0, etc).

    -------------------------------------------------------------
    README DEBE INCLUIR
    -------------------------------------------------------------

    - Arquitectura del contrato.
    - Decisiones de diseño.
    - Medidas de seguridad implementadas.
    - Posibles mejoras futuras.
    - Riesgos conocidos.

    -------------------------------------------------------------
    MENTALIDAD DEL PROYECTO
    -------------------------------------------------------------

    Este proyecto debe demostrar:

    ✔ Comprensión de msg.sender vs tx.origin
    ✔ Dominio del patrón Checks-Effects-Interactions
    ✔ Conocimiento de Reentrancy
    ✔ Conocimiento de Storage Layout
    ✔ Preparación para upgradeabilidad
    ✔ Enfoque en seguridad real

    Si esto se implementa correctamente,
    el proyecto deja de ser "junior practice"
    y se convierte en una pieza de portafolio profesional.
*/
pragma solidity 0.8.28;
