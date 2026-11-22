// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts@5.7.0/token/ERC20/ERC20.sol";

/**
 * @title LoteriaToken
 * @notice Token ERC-20
 *         El contrato conserva inicialmente todos los tokens y los vende
 *         a cambio de ETH de prueba en Remix VM / Sepolia.
 */
contract LoteriaToken is ERC20 {

    uint256 public constant PRECIO_TOKEN = 0.001 ether;
    uint256 public constant SUMINISTRO_INICIAL = 1_000_000;

    event TokensComprados(
        address indexed comprador,
        uint256 cantidadTokens,
        uint256 etherPagado
    );

    constructor() ERC20("Loteria Token", "LOT") {
        _mint(
            address(this),
            SUMINISTRO_INICIAL * 10 ** decimals()
        );
    }

    function comprarTokens(uint256 cantidadTokens) external payable {
        require(
            cantidadTokens > 0,
            "La cantidad debe ser mayor que cero"
        );

        uint256 costo = cantidadTokens * PRECIO_TOKEN;

        require(
            msg.value == costo,
            "Cantidad de ETH incorrecta"
        );

        uint256 unidades =
            cantidadTokens * 10 ** decimals();

        require(
            balanceOf(address(this)) >= unidades,
            "Tokens insuficientes en el contrato"
        );

        _transfer(
            address(this),
            msg.sender,
            unidades
        );

        emit TokensComprados(
            msg.sender,
            cantidadTokens,
            msg.value
        );
    }

    function tokensDisponibles()
        external
        view
        returns (uint256)
    {
        return
            balanceOf(address(this))
            / 10 ** decimals();
    }
}

contract Loteria {

    LoteriaToken public token;

    constructor(address direccionToken) {
        require(
            direccionToken != address(0),
            "Direccion de token invalida"
        );

        token = LoteriaToken(direccionToken);
    }
}