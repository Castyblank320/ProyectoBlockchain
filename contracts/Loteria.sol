// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// USO ACADEMICO: la seleccion del ganador NO es segura para dinero real.
import "@openzeppelin/contracts@5.7.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@5.7.0/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@5.7.0/access/Ownable.sol";
import "@openzeppelin/contracts@5.7.0/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts@5.7.0/utils/Pausable.sol";

// -------------------------------------------------------------
// 1. LOTERIATOKEN (igual que la clase)
// -------------------------------------------------------------
contract LoteriaToken is ERC20 {
    uint256 public constant PRECIO_TOKEN = 0.001 ether;
    uint256 public constant SUMINISTRO_INICIAL = 1_000_000;

    event TokensComprados(
        address indexed comprador,
        uint256 cantidadTokens,
        uint256 etherPagado
    );

    constructor() ERC20("Loteria Token", "LOT") {
        _mint(address(this), SUMINISTRO_INICIAL * 10 ** decimals());
    }

    function comprarTokens(uint256 cantidadTokens) external payable {
        require(cantidadTokens > 0, "La cantidad debe ser mayor que cero");
        uint256 costo = cantidadTokens * PRECIO_TOKEN;
        require(msg.value == costo, "Cantidad de ETH incorrecta");
        uint256 unidades = cantidadTokens * 10 ** decimals();
        require(
            balanceOf(address(this)) >= unidades,
            "Tokens insuficientes en el contrato"
        );
        _transfer(address(this), msg.sender, unidades);
        emit TokensComprados(msg.sender, cantidadTokens, msg.value);
    }

    function tokensDisponibles() external view returns (uint256) {
        return balanceOf(address(this)) / 10 ** decimals();
    }
}

// -------------------------------------------------------------
// 2. BOLETONFT (igual que la clase)
// -------------------------------------------------------------
contract BoletoNFT is ERC721, Ownable {
    event BoletoCreado(
        address indexed comprador,
        uint256 indexed numeroBoleto
    );

    constructor()
        ERC721("Boleto Loteria", "BLT")
        Ownable(msg.sender)
    {}

    function crearBoleto(address comprador, uint256 numeroBoleto)
        external
        onlyOwner
    {
        _safeMint(comprador, numeroBoleto);
        emit BoletoCreado(comprador, numeroBoleto);
    }
}

// -------------------------------------------------------------
// 3. LOTERIA con las 3 mejoras
// -------------------------------------------------------------
contract Loteria is Ownable, ReentrancyGuard, Pausable {
    LoteriaToken public token;
    BoletoNFT public boletoNFT;

    // MEJORA 1: precio configurable (antes constant)
    uint256 public precioBoletoTokens = 10;
    uint256 public constant MAX_BOLETOS_POR_COMPRA = 5;

    // MEJORA 2: límite por usuario
    uint256 public maxBoletosPorUsuario = 10;

    uint256 public siguienteBoleto = 1;
    uint256 public premioAcumulado;

    bool public sorteoRealizado;
    uint256 public boletoGanador;
    address public ganador;
    uint256 public premioPagado;

    struct Boleto {
        uint256 numero;
        address comprador;
    }

    mapping(uint256 => Boleto) public boletos;
    mapping(address => uint256[]) private boletosPorUsuario;
    mapping(address => uint256) public boletosCompradosPorUsuario; // MEJORA 2

    // MEJORA 4 opcional: estadísticas
    uint256 public totalBoletosVendidos;
    uint256 public totalLOTRecaudado;

    event BoletosComprados(
        address indexed comprador,
        uint256 cantidad,
        uint256 costoTotal
    );
    event GanadorSeleccionado(
        uint256 indexed numeroBoleto,
        address indexed receptorPremio,
        uint256 cantidadLOT
    );
    event PrecioBoletoActualizado(uint256 nuevoPrecio);
    event MaxBoletosActualizado(uint256 nuevoMaximo);

    constructor(address direccionToken, address direccionNFT)
        Ownable(msg.sender)
    {
        require(direccionToken != address(0), "Direccion de token invalida");
        require(direccionNFT != address(0), "Direccion de NFT invalida");
        token = LoteriaToken(direccionToken);
        boletoNFT = BoletoNFT(direccionNFT);
    }

    function precioBoletoEnUnidades() public view returns (uint256) {
        return precioBoletoTokens * 10 ** token.decimals();
    }

    function totalBoletos() external view returns (uint256) {
        return siguienteBoleto - 1;
    }

    // --- MEJORA 1: admin del precio ---
    function setPrecioBoleto(uint256 nuevoPrecio) external onlyOwner {
        require(nuevoPrecio > 0, "Precio debe ser mayor a cero");
        require(!sorteoRealizado, "Sorteo ya realizado");
        precioBoletoTokens = nuevoPrecio;
        emit PrecioBoletoActualizado(nuevoPrecio);
    }

    // --- MEJORA 2: admin del límite ---
    function setMaxBoletosPorUsuario(uint256 nuevoMaximo) external onlyOwner {
        require(nuevoMaximo > 0, "Maximo debe ser mayor a cero");
        maxBoletosPorUsuario = nuevoMaximo;
        emit MaxBoletosActualizado(nuevoMaximo);
    }

    // --- MEJORA 3: pausar / reanudar ---
    function pausar() external onlyOwner {
        _pause();
    }

    function reanudar() external onlyOwner {
        _unpause();
    }

    function comprarBoletos(uint256 cantidad)
        external
        nonReentrant
        whenNotPaused
    {
        require(!sorteoRealizado, "La loteria ya fue sorteada");
        require(cantidad > 0, "Debe comprar al menos un boleto");
        require(
            cantidad <= MAX_BOLETOS_POR_COMPRA,
            "Maximo 5 boletos por compra"
        );
        require(
            boletoNFT.owner() == address(this),
            "Falta transferir la administracion del NFT a Loteria"
        );

        // MEJORA 2: verificar límite por usuario
        require(
            boletosCompradosPorUsuario[msg.sender] + cantidad
                <= maxBoletosPorUsuario,
            "Excede el maximo de boletos por usuario"
        );

        uint256 costoTotal = cantidad * precioBoletoEnUnidades();
        require(
            token.balanceOf(msg.sender) >= costoTotal,
            "Balance LOT insuficiente"
        );
        require(
            token.allowance(msg.sender, address(this)) >= costoTotal,
            "Allowance insuficiente"
        );
        require(
            token.transferFrom(msg.sender, address(this), costoTotal),
            "No se pudieron transferir los LOT"
        );

        for (uint256 i = 0; i < cantidad; i++) {
            uint256 numero = siguienteBoleto;
            boletos[numero] = Boleto({numero: numero, comprador: msg.sender});
            boletosPorUsuario[msg.sender].push(numero);
            boletoNFT.crearBoleto(msg.sender, numero);
            siguienteBoleto++;
        }

        boletosCompradosPorUsuario[msg.sender] += cantidad;
        premioAcumulado += costoTotal;
        totalBoletosVendidos += cantidad;
        totalLOTRecaudado += costoTotal;

        emit BoletosComprados(msg.sender, cantidad, costoTotal);
    }

    function obtenerBoletos(address usuario)
        external
        view
        returns (uint256[] memory)
    {
        return boletosPorUsuario[usuario];
    }

    // SOLO ACADEMICO: block.prevrandao y block.timestamp NO son seguros.
    function sortearGanador() external onlyOwner nonReentrant whenNotPaused {
        require(!sorteoRealizado, "Sorteo ya realizado");

        uint256 cantidadBoletos = siguienteBoleto - 1;
        require(cantidadBoletos > 0, "No hay boletos vendidos");

        uint256 premio = premioAcumulado;
        require(premio > 0, "No existe premio acumulado");

        uint256 semilla = uint256(
            keccak256(
                abi.encodePacked(
                    block.prevrandao,
                    block.timestamp,
                    block.number,
                    address(this),
                    cantidadBoletos
                )
            )
        );

        uint256 numeroElegido = (semilla % cantidadBoletos) + 1;
        address receptor = boletoNFT.ownerOf(numeroElegido);

        // Efectos ANTES de la transferencia
        sorteoRealizado = true;
        boletoGanador = numeroElegido;
        ganador = receptor;
        premioPagado = premio;
        premioAcumulado = 0;

        require(token.transfer(receptor, premio), "No se pudo pagar el premio");

        emit GanadorSeleccionado(numeroElegido, receptor, premio);
    }
}