FROM alpine:3.13

ENV TZ=Europe/Kiev

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN apk add --no-cache git python3 python3-dev py3-pip nodejs npm bind-tools netcat-openbsd curl make gcc musl-dev
RUN git clone https://github.com/fetchai/mettalex-market-maker.git

WORKDIR /mettalex-market-maker/on-chain
RUN make init

COPY scripts/mettalex_contract_setup.py scripts/mettalex_contract_setup.py
RUN curl https://raw.githubusercontent.com/eficode/wait-for/master/wait-for -o ./wait-for && chmod +x ./wait-for

CMD ./wait-for ganache-cli:8545 -- /bin/sh -c "cd scripts && python3 mettalex_contract_setup.py -a setup -n $(dig +short ganache-cli):8545 -v 3 && sh"

