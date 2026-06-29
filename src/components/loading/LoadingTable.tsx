"use client";

type Props = {
  loadings: any[];
  search: string;
  setSearch: (v: string) => void;
};

export default function LoadingTable({
  loadings,
  search,
  setSearch,
}: Props) {
  return (
    <div className="mt-10">

      <h2 className="text-2xl font-bold mb-4 text-gray-900">
        My Loadings
      </h2>

      <input
        type="text"
        placeholder="Search Loading..."
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="w-full border rounded-lg p-3 mb-4 bg-white text-gray-900"
      />

      <div className="overflow-x-auto">

        <table className="w-full border border-gray-200 bg-white">

          <thead className="bg-blue-600 text-white">

            <tr>

              <th className="p-3 text-left">
                Loading No
              </th>

              <th className="p-3 text-left">
                Date
              </th>

              <th className="p-3 text-left">
                Vehicle
              </th>

              <th className="p-3 text-left">
                Driver
              </th>

              <th className="p-3 text-left">
                Route
              </th>

            </tr>

          </thead>

          <tbody>

            {loadings
              .filter((item: any) =>
                item.loading_no
                  ?.toLowerCase()
                  .includes(search.toLowerCase())
              )
              .map((item: any) => (

                <tr
                  key={item.id}
                  className="border-b hover:bg-gray-50"
                >

                  <td className="p-3 text-gray-900">
                    {item.loading_no}
                  </td>

                  <td className="p-3 text-gray-900">
                    {item.loading_date}
                  </td>

                  <td className="p-3 text-gray-900">
                    {item.vehicles?.vehicle_no}
                  </td>

                  <td className="p-3 text-gray-900">
                    {item.drivers?.name}
                  </td>

                  <td className="p-3 text-gray-900">
                    {item.route}
                  </td>

                </tr>

              ))}

          </tbody>

        </table>

      </div>

    </div>
  );
}