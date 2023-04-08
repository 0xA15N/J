import React, { useState, useEffect } from 'react'
import axios from 'axios'

const ETH_TO_USD_API_URL = 'https://min-api.cryptocompare.com/data/price'

const Loading = ({
  isFinalPrize,
  isCalculation,
}: {
  isFinalPrize: boolean
  isCalculation: boolean
}) => {
  return (
    <>
      <div className="animate-pulse mb-1 mr-2">
        <div
          className={`${isFinalPrize ? 'bg-[#f49c5c]' : 'bg-slate-500'} ${
            isCalculation ? 'h-3 w-7' : 'h-6 w-16'
          } rounded`}
        ></div>
      </div>
    </>
  )
}

const TotalPrice = ({
  regPeriod,
  priceToPay,
}: {
  regPeriod: number
  priceToPay: number
}) => {
  return (
    <>
      <div className="px-12 py-8 bg-[#334155] lg:py-0">
        <p className="text-[#91A3B8] font-medium text-sm lg:text-xs xl:text-sm">
          Estimated Total Price
        </p>
        <div className="flex items-center text-white font-semibold text-2xl lg:text-lg xl:text-2xl">
          {priceToPay ? (
            priceToPay.toFixed(2)
          ) : (
            <Loading isFinalPrize={false} isCalculation={false} />
          )}{' '}
          FLR
        </div>
      </div>
    </>
  )
}

const GasFee = ({ fee }: { fee: number }) => {
  return (
    <>
      <div className="px-12 py-8 bg-[#334155] lg:py-0">
        <p className="text-[#91A3B8] font-medium text-sm lg:text-xs xl:text-sm">
          Gas Fee (at most)
        </p>
        <p className="text-white font-semibold text-2xl lg:text-lg xl:text-2xl">
          {(fee / 10 ** 18).toFixed(9)} FLR
        </p>
      </div>
    </>
  )
}

const FinalPrice = ({
  regPeriod,
  fee,
  priceToPay,
}: {
  regPeriod: number
  fee: number
  priceToPay: number
}) => {
  const [ethPrice, setEthPrice] = useState<number>(0)

  useEffect(() => {
    axios
      .get(ETH_TO_USD_API_URL, {
        params: {
          fsym: 'FLR',
          tsyms: 'USD',
        },
      })
      .then((response) => {
        const priceData = response.data
        const price = priceData['USD']
        // console.log('price', price)
        setEthPrice(price)
      })
      .catch((error) => {
        console.error(error)
      })
  }, [])

  return (
    <>
      <div className="flex flex-col text-center items-center w-full bg-[#F97316] h-32 py-6 rounded-b-lg lg:rounded-bl-none lg:rounded-r-lg lg:w-1/3">
        <div className="px-20 flex flex-col justify-center items-center text-center lg:px-10">
          <p className="text-[#FED7AA] text-xs">At most</p>
          <div className="flex items-center text-white font-semibold text-2xl lg:text-lg xl:text-2xl">
            {priceToPay ? (
              (priceToPay + fee / 10 ** 18).toFixed(2)
            ) : (
              <Loading isFinalPrize={true} isCalculation={false} />
            )}{' '}
            FLR
          </div>
          <div className="flex items-center text-[#FED7AA] text-xs">
            <p className="text-[#FED7AA] text-xs mr-1">Calculated to</p>
            <span className="font-semibold text-white flex items-center">
              $
              {priceToPay ? (
                ((priceToPay + fee / 10 ** 18) * ethPrice).toFixed(2)
              ) : (
                <Loading isFinalPrize={true} isCalculation={true} />
              )}{' '}
              USD
            </span>
          </div>
        </div>
      </div>
    </>
  )
}

export default function Final_price({
  regPeriod,
  fee,
  priceToPay,
}: {
  regPeriod: number
  fee: number
  priceToPay: number
}) {
  return (
    <div className="flex flex-col items-center mt-9 h-96 w-full bg-[#334155] rounded-t-lg lg:flex-row lg:rounded-l-lg lg:h-32">
      <div className="bg-[#334155] flex flex-col items-center w-full lg:w-2/3 lg:flex-row">
        <TotalPrice regPeriod={regPeriod} priceToPay={priceToPay} />

        {/* + */}
        <div className="text-white text-xl">+</div>

        <GasFee fee={fee} />
      </div>

      {/* Final Price -- TODO change 0.011 with gas fee */}
      <FinalPrice regPeriod={regPeriod} fee={fee} priceToPay={priceToPay} />
    </div>
  )
}
