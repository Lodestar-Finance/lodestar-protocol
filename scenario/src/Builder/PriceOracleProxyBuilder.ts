import {Event} from '../Event';
import {addAction, World} from '../World';
import {PriceOracleProxy} from '../Contract/PriceOracleProxy';
import {Invokation} from '../Invokation';
import {Arg, Fetcher, getFetcherValue} from '../Command';
import {storeAndSaveContract} from '../Networks';
import {getContract} from '../Contract';
import {getAddressV} from '../CoreValue';
import {AddressV} from '../Value';

const PriceOracleProxyContract = getContract("PriceOracleProxyETH");

export interface PriceOracleProxyData {
  invokation?: Invokation<PriceOracleProxy>,
  contract?: PriceOracleProxy,
  description: string,
  address?: string,
  cETH: string,
  flags: string,
  plvGLP: string,
  GLP: string
  //cUSDC: string,
  //cDAI: string
}

export async function buildPriceOracleProxy(world: World, from: string, event: Event): Promise<{world: World, priceOracleProxy: PriceOracleProxy, invokation: Invokation<PriceOracleProxy>}> {
  const fetchers = [
    new Fetcher<{guardian: AddressV, priceOracle: AddressV, aggregator: AddressV, flags: AddressV, cETH: AddressV, plvGLP: AddressV, GLP: AddressV}, PriceOracleProxyData>(`
        #### Price Oracle Proxy
        * "Deploy <Guardian:Address> <PriceOracle:Address> <cETH:Address> <cUSDC:Address> <cSAI:Address> <cDAI:Address> <cUSDT:Address>" - The Price Oracle which proxies to a backing oracle
        * E.g. "PriceOracleProxy Deploy Admin (PriceOracle Address) cETH cUSDC cSAI cDAI cUSDT"
      `,
      "PriceOracleProxyETH",
      [
        // Comptroller?
        new Arg("guardian", getAddressV),
        new Arg("priceOracle", getAddressV),
        new Arg("aggregator", getAddressV),
        new Arg("cETH", getAddressV),
        new Arg("flags", getAddressV),
        new Arg("plvGLP", getAddressV),
        new Arg("GLP", getAddressV)
        //new Arg("cSAI", getAddressV),
        //new Arg("cDAI", getAddressV),
        //new Arg("cUSDT", getAddressV)
      ],
      async (world, {guardian, priceOracle, aggregator, flags, cETH, plvGLP, GLP}) => {
        return {
          invokation: await PriceOracleProxyContract.deploy<PriceOracleProxy>(world, from, [guardian.val, priceOracle.val, aggregator.val, flags.val, cETH.val]),
          description: "Price Oracle Proxy",
          cETH: cETH.val,
          flags: flags.val,
          plvGLP: plvGLP.val,
          GLP: GLP.val
          //cUSDC: cUSDC.val,
          //cSAI: cSAI.val,
          //cDAI: cDAI.val,
          //cUSDT: cUSDT.val
        };
      },
      {catchall: true}
    )
  ];

  let priceOracleProxyData = await getFetcherValue<any, PriceOracleProxyData>("DeployPriceOracleProxy", fetchers, world, event);
  let invokation = priceOracleProxyData.invokation!;
  delete priceOracleProxyData.invokation;

  if (invokation.error) {
    throw invokation.error;
  }
  const priceOracleProxy = invokation.value!;
  priceOracleProxyData.address = priceOracleProxy._address;

  world = await storeAndSaveContract(
    world,
    priceOracleProxy,
    'PriceOracleProxyETH',
    invokation,
    [
      { index: ['PriceOracleProxyETH'], data: priceOracleProxyData }
    ]
  );

  return {world, priceOracleProxy, invokation};
}