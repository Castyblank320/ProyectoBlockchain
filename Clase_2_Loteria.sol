// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts@5.7.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@5.7.0/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@5.7.0/access/Ownable.sol";

/**
 * @title LoteriaToken
 * @notice Token ERC-20 académico creado en la Clase 1.
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


/**
 * @title BoletoNFT
 * @notice Cada boleto de lotería se representa mediante un NFT ERC-721.
 *         Una vez configurado el sistema, solo Loteria será owner de este
 *         contrato y por tanto, solo Loteria podrá crear boletos.
 */
contract BoletoNFT is ERC721, Ownable {

    event BoletoCreado(
        address indexed comprador,
        uint256 indexed numeroBoleto
    );

    constructor()
        ERC721("Boleto Loteria", "BLT")
        Ownable(msg.sender)
    {}

    function crearBoleto(
        address comprador,
        uint256 numeroBoleto
    )
        external
        onlyOwner
    {
        _safeMint(comprador, numeroBoleto);

        emit BoletoCreado(
            comprador,
            numeroBoleto
        );
    }
}


/**
 * @title Loteria
 * @notice En esta clase se implementa la compra de boletos con LOT.
 *         El sorteo y pago del ganador se incorporarán en la Clase 3.
 */
contract Loteria {

    LoteriaToken public token;
    BoletoNFT public boletoNFT;

    uint256 public constant PRECIO_BOLETO_TOKENS = 10;
    uint256 public constant MAX_BOLETOS_POR_COMPRA = 5;

    uint256 public siguienteBoleto = 1;

    // Se expresa en unidades mínimas del ERC-20.
    uint256 public premioAcumulado;

    struct Boleto {
        uint256 numero;
        address comprador;
    }

    mapping(uint256 => Boleto) public boletos;
    mapping(address => uint256[]) private boletosPorUsuario;

    event BoletosComprados(
        address indexed comprador,
        uint256 cantidad,
        uint256 costoTotal
    );

    constructor(
        address direccionToken,
        address direccionNFT
    ) {
        require(
            direccionToken != address(0),
            "Direccion de token invalida"
        );

        require(
            direccionNFT != address(0),
            "Direccion de NFT invalida"
        );

        token = LoteriaToken(direccionToken);
        boletoNFT = BoletoNFT(direccionNFT);
    }

    /**
     * @notice Precio de un boleto expresado en las unidades mínimas del ERC-20.
     */
    function precioBoletoEnUnidades()
        public
        view
        returns (uint256)
    {
        return
            PRECIO_BOLETO_TOKENS
            * 10 ** token.decimals();
    }

    /**
     * @notice Compra entre 1 y 5 boletos.
     * @dev El usuario debe ejecutar primero approve sobre LoteriaToken,
     *      autorizando a este contrato Loteria a gastar los LOT necesarios.
     */
    function comprarBoletos(uint256 cantidad) external {
        require(
            cantidad > 0,
            "Debe comprar al menos un boleto"
        );

        require(
            cantidad <= MAX_BOLETOS_POR_COMPRA,
            "Maximo 5 boletos por compra"
        );

        uint256 costoTotal =
            cantidad * precioBoletoEnUnidades();

        require(
            token.balanceOf(msg.sender) >= costoTotal,
            "Balance LOT insuficiente"
        );

        require(
            token.allowance(
                msg.sender,
                address(this)
            ) >= costoTotal,
            "Allowance insuficiente"
        );

        bool transferenciaCorrecta =
            token.transferFrom(
                msg.sender,
                address(this),
                costoTotal
            );

        require(
            transferenciaCorrecta,
            "No se pudieron transferir los LOT"
        );

        for (uint256 i = 0; i < cantidad; i++) {
            uint256 numero = siguienteBoleto;

            boletos[numero] = Boleto({
                numero: numero,
                comprador: msg.sender
            });

            boletosPorUsuario[msg.sender].push(numero);

            boletoNFT.crearBoleto(
                msg.sender,
                numero
            );

            siguienteBoleto++;
        }

        premioAcumulado += costoTotal;

        emit BoletosComprados(
            msg.sender,
            cantidad,
            costoTotal
        );
    }

    function obtenerBoletos(address usuario)
        external
        view
        returns (uint256[] memory)
    {
        return boletosPorUsuario[usuario];
    }
}