
#
# InfiniteMPS
#

# TODO: store the cell 1 as an MPS
# Implement `getcell(::InfiniteMPS, n::Integer) -> MPS`
mutable struct InfiniteMPS <: AbstractInfiniteMPS
  data::CelledVector{ITensor}
  llim::Int #RealInfinity
  rlim::Int #RealInfinity
  reverse::Bool
end

#
# InfiniteCanonicalMPS
#

# L and R are the orthogonalized MPS tensors.
# C are the center bond matrices (singular values of C
# are the singular values of the MPS at the specified
# cut)
struct InfiniteCanonicalMPS <: AbstractInfiniteMPS
  AL::InfiniteMPS
  C::InfiniteMPS
  AR::InfiniteMPS
end

# TODO: check if `isempty(ψ.AL)`, if so use `ψ.AR`
nsites(ψ::InfiniteCanonicalMPS) = nsites(ψ.AL)
isreversed(ψ::InfiniteCanonicalMPS) = isreversed(ψ.AL)
#ITensors.data(ψ::InfiniteCanonicalMPS) = data(ψ.AL)
ITensors.data(ψ::InfiniteCanonicalMPS) = ψ.AL.data

Base.copy(ψ::InfiniteCanonicalMPS) = InfiniteCanonicalMPS(copy(ψ.AL), copy(ψ.C), copy(ψ.AR))

function fmap(f, ψ::InfiniteCanonicalMPS)
  return InfiniteCanonicalMPS(f(ψ.AL), f(ψ.C), f(ψ.AR))
end

function ITensors.prime(ψ::InfiniteCanonicalMPS, args...; kwargs...)
  return fmap(x -> prime(x, args...; kwargs...), ψ)
end

function ITensors.prime(f::typeof(linkinds), ψ::InfiniteCanonicalMPS, args...; kwargs...)
  # Doesn't prime ψ.C
  #return fmap(x -> prime(f, x, args...; kwargs...), ψ)
  AL = prime(linkinds, ψ.AL, args...; kwargs...)
  C = prime(ψ.C, args...; kwargs...)
  AR = prime(linkinds, ψ.AR, args...; kwargs...)
  return InfiniteCanonicalMPS(AL, C, AR)
end

function ITensors.dag(ψ::InfiniteCanonicalMPS, args...; kwargs...)
  return fmap(x -> dag(x, args...; kwargs...), ψ)
end

ITensors.siteinds(f::typeof(only), ψ::InfiniteCanonicalMPS) = siteinds(f, ψ.AL)

getcell(i::Index) = ITensorInfiniteMPS.getcell(tags(i))
getsite(i::Index) = getsite(tags(i))

#Before, for a two site Hamiltonian, findsites(ψ, H[3]) would return [1, 2]
#Appeared unsafe for index purpose
function ITensors.findfirstsiteind(ψ::InfiniteMPS, i::Index)
  c = ITensorInfiniteMPS.getcell(i)
  n1 = getsite(i)
  return (c - 1) * nsites(ψ) + n1
end

function ITensors.findsites(ψ::InfiniteMPS, T::MPO)
  s = [noprime(filterinds(T[x]; plev=1)[1]) for x in 1:length(T)]
  return sort([ITensors.findfirstsiteind(ψ, i) for i in s])
end
ITensors.findsites(ψ::InfiniteCanonicalMPS, T::MPO) = findsites(ψ.AL, T)

#Kept for historical reason
function ITensors.findsites(ψ::InfiniteMPS, T::ITensor)
  s = filterinds(T; plev=0)
  return sort([ITensors.findfirstsiteind(ψ, i) for i in s])
end
ITensors.findsites(ψ::InfiniteCanonicalMPS, T::ITensor) = findsites(ψ.AL, T)

# For now, only represents nearest neighbor interactions
# on a linear chain
struct InfiniteSum{T}
  data::CelledVector{T}
end
InfiniteSum{T}(N::Int) where {T} = InfiniteSum{T}(Vector{T}(undef, N))
InfiniteSum{T}(data::Vector{T}) where {T} = InfiniteSum{T}(CelledVector(data))

# Automatically converts from ITensor to MPO.
# XXX: check this conversion is correct.
InfiniteSum{T}(data::Vector{ITensor}) where {T} = InfiniteSum{T}(CelledVector(T.(data)))

function Base.getindex(l::InfiniteSum, n1n2::Tuple{Int,Int})
  n1, n2 = n1n2
  @assert n2 == n1 + 1
  return l.data[n1]
end
function Base.getindex(l::InfiniteSum, n1::Int)
  return l.data[n1]
end
nsites(h::InfiniteSum) = length(h.data)
#Gives the range of the Hamiltonian. Useful for better optimized contraction in VUMPS
nsites_support(h::InfiniteSum) = length.(h.data)
nsites_support(h::InfiniteSum, n::Int64) = length(h.data[n])

nrange(h::InfiniteSum) = nrange.(h.data, ncell=nsites(h))
nrange(h::InfiniteSum, n::Int64) = nrange(h.data[n]; ncell=nsites(h))
function nrange(h::MPO; ncell=1)
  ns = findsites(h; ncell=ncell)
  return ns[end] - ns[1] + 1
end

ITensors.findsites(h::InfiniteSum) = [findsites(h, n) for n in 1:nsites(h)]
ITensors.findsites(h::InfiniteSum, n::Int64) = findsites(h.data[n]; ncell=nsites(h))
function ITensors.findfirstsiteind(i::Index, ncell::Int64)
  c = ITensorInfiniteMPS.getcell(i)
  n1 = getsite(i)
  return (c - 1) * ncell + n1
end
function ITensors.findsites(h::MPO; ncell::Int64=1)
  s = [filterinds(h[x]; plev=1)[1] for x in 1:length(h)]
  return sort([ITensors.findfirstsiteind(i, ncell) for i in s])
end

#Kept for historical reasons
function nrange(h::ITensor; ncell=0)
  ns = findsites(h; ncell=ncell)
  return ns[end] - ns[1] + 1
end
function ITensors.findfirstsiteind(h::ITensor, i::Index, ncell::Int64)
  c = getcell(i)
  n1 = getsite(i)
  return (c - 1) * ncell + n1
end
function ITensors.findsites(h::ITensor; ncell::Int64=1)
  s = filterinds(h; plev=0)
  return sort([ITensors.findfirstsiteind(h, i, ncell) for i in s])
end

## HDF5 support for the InfiniteCanonicalMPS type

function HDF5.write(
  parent::Union{HDF5.File,HDF5.Group}, name::AbstractString, ψ::InfiniteCanonicalMPS
)
  g = create_group(parent, name)
  attributes(g)["type"] = "InfiniteCanonicalMPS"
  attributes(g)["version"] = 1
  N = nsites(ψ)
  write(g, "length", N)
  for n in 1:N
    write(g, "AL[$(n)]", ψ.AL[n])
    write(g, "AR[$(n)]", ψ.AR[n])
    write(g, "C[$(n)]", ψ.C[n])
  end
end

function HDF5.read(
  parent::Union{HDF5.File,HDF5.Group}, name::AbstractString, ::Type{InfiniteCanonicalMPS}
)
  g = open_group(parent, name)
  if read(attributes(g)["type"]) != "InfiniteCanonicalMPS"
    error("HDF5 group or file does not contain InfiniteCanonicalMPS data")
  end
  N = read(g, "length")
  AL = InfiniteMPS([read(g, "AL[$(i)]", ITensor) for i in 1:N])
  AR = InfiniteMPS([read(g, "AR[$(i)]", ITensor) for i in 1:N])
  C = InfiniteMPS([read(g, "C[$(i)]", ITensor) for i in 1:N])
  return InfiniteCanonicalMPS(AL, C, AR)
end
