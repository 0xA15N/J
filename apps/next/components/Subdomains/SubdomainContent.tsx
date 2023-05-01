import React, { useState } from 'react'
import Question from '../../public/Question.svg'
import Plus from '../../public/Plus.svg'
import Image from 'next/image'
import SubdomainLine from './SubdomainLine'
import Link from 'next/link'

const AddSubdomain = ({
  arrSubdomains,
  checkOwnerDomain,
}: {
  arrSubdomains: Array<any>
  checkOwnerDomain: boolean
}) => {
  const [isOpen, setIsOpen] = useState(false)
  const [input, setInput] = useState('')
  return (
    <>
      <div className="flex flex-row items-center mt-5 bg-gray-800 px-8 py-12 lg:mt-0">
        {isOpen ? (
          <>
            <form
              // onSubmit={handleSubmit}
              className="flex items-center w-3/5 py-2 px-4 h-12 rounded-md bg-gray-700 border-2 border-gray-500"
            >
              <input
                type="text"
                name="input-field"
                value={input}
                onChange={(e) => {
                  setInput(e.target.value)
                }}
                className="w-full bg-transparent font-normal text-base text-white border-0 focus:outline-none placeholder:text-gray-300 placeholder:font-normal focus:bg-transparent"
                placeholder="Type in a label for your subdomain"
                required
              />
            </form>
            <div className="items-center flex ml-auto">
              {/* Cancel */}
              <button
                onClick={() => setIsOpen(false)}
                className="flex items-center justify-center px-3 py-2 border border-gray-400 rounded-lg mr-2 hover:scale-105 transform transition duration-300 ease-out"
              >
                <p className="text-gray-400 text-medium text-xs">Cancel</p>
              </button>

              {/* Save */}
              <button
                // onClick={() => save()}
                disabled={input === ''}
                type="submit"
                value="Submit"
                className="flex justify-center items-center text-center bg-[#F97316] px-3 py-2 rounded-lg text-white border border-[#F97316] hover:scale-105 transform transition duration-300 ease-out lg:ml-auto disabled:border-gray-500 disabled:bg-gray-500 disabled:hover:scale-100"
              >
                <p className="text-xs font-medium">Save</p>
              </button>
            </div>
          </>
        ) : (
          <>
            {/* No subdomains have been added yet */}
            {typeof arrSubdomains !== 'undefined' &&
              arrSubdomains.length === 0 && (
                <div
                  className={`flex w-full ${
                    checkOwnerDomain ? `lg:w-3/4` : 'lg:w-full'
                  } bg-gray-500 py-3 px-5 rounded-lg mr-4`}
                >
                  <Image className="h-4 w-4 mr-2" src={Question} alt="FNS" />
                  <div className="flex-col">
                    <p className="text-gray-200 font-semibold text-sm">
                      No subdomains have been added yet
                    </p>
                  </div>
                </div>
              )}
            {/* Button */}
            {checkOwnerDomain && (
              <button
                onClick={() => setIsOpen(true)}
                className="flex justify-center items-center text-center bg-[#F97316] h-11 w-1/2 rounded-lg text-white px-auto hover:scale-105 transform transition duration-100 ease-out md:w-1/4 lg:ml-auto"
              >
                <p className="text-xs font-medium mr-2">Add Subdomain</p>
                <Image className="h-4 w-4" src={Plus} alt="FNS" />
              </button>
            )}
          </>
        )}
      </div>
    </>
  )
}

export default function SubdomainContent({
  arrSubdomains,
  checkOwnerDomain,
}: {
  arrSubdomains: Array<any>
  checkOwnerDomain: boolean
}) {
  return (
    <>
      <AddSubdomain
        arrSubdomains={arrSubdomains}
        checkOwnerDomain={checkOwnerDomain}
      />

      {arrSubdomains.length > 0 && (
        <div className="flex-col bg-gray-800 px-8 py-5 rounded-b-md">
          {arrSubdomains.map((item, index) => (
            <Link
              key={index}
              href={{
                pathname: '/details',
                query: { result: item },
              }}
            >
              <SubdomainLine key={index} data={item} />
            </Link>
          ))}
        </div>
      )}
    </>
  )
}
