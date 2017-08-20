type RHS_IIF_Scalar{F,CType,tType,aType} <: Function
  f::F
  t::tType
  dt::tType
  tmp::CType
  a::aType
end

function (p::RHS_IIF_Scalar)(u,resid)
  resid[1] = first(u) - p.tmp - p.a*p.dt*first(p.f.f2(p.t+p.dt,first(u)))
end

function initialize!(integrator,cache::Union{GenericIIF1ConstantCache,GenericIIF2ConstantCache})
  integrator.kshortsize = 2
  integrator.k = eltype(integrator.sol.k)(integrator.kshortsize)
  A = integrator.f.f1
  cache.uhold[1] = integrator.f.f2(integrator.t,integrator.uprev)
  integrator.fsalfirst = integrator.f.f1(integrator.t,integrator.uprev) .+ cache.uhold[1]

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsalfirst
end

function perform_step!(integrator,cache::Union{GenericIIF1ConstantCache,GenericIIF2ConstantCache},repeat_step=false)
  @unpack t,dt,uprev,u,f = integrator
  @unpack uhold,rhs,nl_rhs = cache

  # If adaptive, this should be computed after and cached
  A = integrator.f.f1
  if typeof(cache) <: GenericIIF1ConstantCache
    tmp = expm(A*dt)*(uprev)
  elseif typeof(cache) <: GenericIIF2ConstantCache
    @muladd tmp = expm(A*dt)*(@. uprev + 0.5dt*uhold[1]) # This uhold only works for non-adaptive
  end

  if integrator.success_iter > 0 && !integrator.u_modified
    uhold[1] = current_extrapolant(t+dt,integrator)
  end # else uhold is previous value.

  rhs.t = t
  rhs.dt = dt
  rhs.tmp = tmp
  nlres = integrator.alg.nlsolve(nl_rhs,uhold)
  uhold[1] = integrator.f.f2(t+dt,nlres[1])
  u = nlres[1]
  integrator.fsallast = A*u .+ uhold[1]
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

type RHS_IIF{F,uType,tType,DiffCacheType,aType} <: Function
  f::F
  tmp::uType
  t::tType
  dt::tType
  dual_cache::DiffCacheType
  a::aType
end
function (p::RHS_IIF)(u,resid)
  du = get_du(p.dual_cache, eltype(u))
  p.f.f2(p.t+p.dt,reshape(u,size(u)),du)
  @. resid = u - p.tmp - p.a*p.dt*du
end

function initialize!(integrator,cache::Union{GenericIIF1Cache,GenericIIF2Cache})
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  integrator.kshortsize = 2
  integrator.k = eltype(integrator.sol.k)(integrator.kshortsize)
  A = integrator.f.f1
  integrator.f.f2(integrator.t,integrator.uprev,cache.rtmp1)
  A_mul_B!(cache.k,A,integrator.uprev)
  @. integrator.fsalfirst = cache.k + cache.rtmp1
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::Union{GenericIIF1Cache,GenericIIF2Cache},repeat_step=false)
  @unpack rtmp1,tmp,k = cache
  @unpack uhold,rhs,nl_rhs = cache
  @unpack t,dt,uprev,u,f = integrator

  @. k = uprev
  if typeof(cache) <: GenericIIF2Cache
    @muladd @. k = k + 0.5dt*rtmp1
  end

  A_mul_B!(tmp,cache.expA,k)

  if integrator.success_iter > 0 && !integrator.u_modified
    current_extrapolant!(uhold,t+dt,integrator)
  end # else uhold is previous value.

  rhs.t = t
  rhs.dt = dt
  rhs.tmp = tmp
  nlres = integrator.alg.nlsolve(nl_rhs,uhold)

  copy!(u,nlres)
  integrator.f.f2(t+dt,nlres,rtmp1)
  A = f.f1
  integrator.fsallast .= A*u .+ rtmp1
end
