import Image from "next/image";

export const Loading = () => {
  return (
    <div>
      <Image src="/loading.svg" alt="Loading" width={100} height={100} />
    </div>
  );
};
